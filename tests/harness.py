"""Boots Vitre in a headless QEMU, captures COM1 and talks QMP."""

import json
import os
import re
import shutil
import socket
import subprocess
import tempfile
import threading
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(ROOT, "build")
IMG = os.path.join(BUILD, "vitre.img")
LOGS = os.path.join(BUILD, "logs")
QEMU = os.environ.get("QEMU", "qemu-system-x86_64")


class TestFailure(Exception):
    pass


def fresh_disk():
    """Private copy of the image, so tests that write to disk stay isolated."""
    fd, path = tempfile.mkstemp(prefix="vitre-", suffix=".img")
    os.close(fd)
    shutil.copyfile(IMG, path)
    return path


class Vm:
    def __init__(self, name, disk=None, net=False, mem="128M", extra=()):
        self.name = name
        self.disk = disk or fresh_disk()
        self.own_disk = disk is None
        self.net = net
        self.mem = mem
        self.extra = list(extra)
        self.out = bytearray()
        self.lock = threading.Lock()
        self.proc = None
        self.qmp_sock = None

    def __enter__(self):
        try:
            self.start()
        except BaseException:
            self.stop()
            raise
        return self

    def __exit__(self, *exc):
        self.stop()

    def start(self):
        os.makedirs(LOGS, exist_ok=True)
        self.tmp = tempfile.mkdtemp(prefix="vitre-qmp-")
        self.qmp_path = os.path.join(self.tmp, "qmp.sock")
        cmd = [
            QEMU, "-machine", "pc", "-m", self.mem,
            "-drive", f"file={self.disk},format=raw,if=ide,index=0",
            "-serial", "stdio", "-display", "none", "-no-reboot",
            "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04",
            "-qmp", f"unix:{self.qmp_path},server=on,wait=off",
        ]
        cmd += ["-nic", "user,model=e1000"] if self.net else ["-nic", "none"]
        cmd += self.extra
        self.log = open(os.path.join(LOGS, f"{self.name}.serial.log"), "wb")
        self.proc = subprocess.Popen(cmd, stdin=subprocess.DEVNULL,
                                     stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.reader = threading.Thread(target=self._reader, daemon=True)
        self.reader.start()

    def _reader(self):
        while True:
            chunk = self.proc.stdout.read1(4096)
            if not chunk:
                break
            with self.lock:
                self.out += chunk
            self.log.write(chunk)
            self.log.flush()

    def serial(self):
        with self.lock:
            return self.out.decode("latin-1")

    def wait_for(self, pattern, timeout=10, start=0):
        """Wait until regex `pattern` appears in serial output after offset `start`."""
        rx = re.compile(pattern)
        deadline = time.time() + timeout
        while True:
            exited = self.proc.poll() is not None
            if exited:
                self.reader.join(timeout=1)
            m = rx.search(self.serial(), start)
            if m:
                return m
            if exited or time.time() > deadline:
                break
            time.sleep(0.02)
        tail = self.serial()[-1500:]
        raise TestFailure(f"timeout waiting for {pattern!r}; serial tail:\n{tail}")

    def wait_exit(self, timeout=10):
        try:
            return self.proc.wait(timeout)
        except subprocess.TimeoutExpired:
            raise TestFailure("QEMU did not exit")

    def _qmp_connect(self):
        deadline = time.time() + 5
        while True:
            try:
                s = socket.socket(socket.AF_UNIX)
                s.connect(self.qmp_path)
                break
            except OSError:
                s.close()
                if time.time() > deadline:
                    raise
                time.sleep(0.05)
        self.qmp_file = s.makefile("rw")
        self.qmp_sock = s
        json.loads(self.qmp_file.readline())
        self.qmp("qmp_capabilities")

    def qmp(self, execute, **arguments):
        if self.qmp_sock is None and execute != "qmp_capabilities":
            self._qmp_connect()
        msg = {"execute": execute}
        if arguments:
            msg["arguments"] = arguments
        self.qmp_file.write(json.dumps(msg) + "\n")
        self.qmp_file.flush()
        while True:
            line = self.qmp_file.readline()
            if not line:
                raise TestFailure(f"QMP {execute}: connection closed")
            reply = json.loads(line)
            if "return" in reply:
                return reply["return"]
            if "error" in reply:
                raise TestFailure(f"QMP {execute}: {reply['error']}")

    def hmp(self, command):
        return self.qmp("human-monitor-command", **{"command-line": command})

    def screendump(self):
        """Returns (width, height, rgb bytes) of the current screen."""
        path = os.path.join(self.tmp, "screen.ppm")
        self.qmp("screendump", filename=path)
        return read_ppm(path)

    def stop(self):
        if self.proc and self.proc.poll() is None:
            self.proc.kill()
            self.proc.wait()
        if getattr(self, "reader", None):
            self.reader.join(timeout=2)
        if self.qmp_sock:
            self.qmp_sock.close()
        if getattr(self, "log", None):
            self.log.close()
        if self.own_disk and os.path.exists(self.disk):
            os.remove(self.disk)
        shutil.rmtree(getattr(self, "tmp", ""), ignore_errors=True)


def read_ppm(path):
    with open(path, "rb") as f:
        data = f.read()
    # The header ends with exactly one whitespace byte; split() would also eat
    # leading pixel bytes that happen to be whitespace values.
    m = re.match(rb"P6\s+(\d+)\s+(\d+)\s+\d+\s", data)
    if not m:
        raise TestFailure(f"not a P6 PPM: {data[:16]!r}")
    w, h = int(m.group(1)), int(m.group(2))
    return w, h, data[m.end(): m.end() + w * h * 3]
