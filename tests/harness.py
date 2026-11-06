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
SHELL_READY = r"\[shell\] ready.*\r\nvitre> "


class TestFailure(Exception):
    pass


def fresh_disk():
    """Private copy of the image, so tests that write to disk stay isolated."""
    fd, path = tempfile.mkstemp(prefix="vitre-", suffix=".img")
    os.close(fd)
    shutil.copyfile(IMG, path)
    return path


class Vm:
    def __init__(self, name, disk=None, net=False, mem="128M", cmdline="", extra=()):
        self.name = name
        self.cmdline = cmdline
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
        if self.cmdline:
            cmd += ["-fw_cfg", f"name=opt/vitre/cmdline,string={self.cmdline.replace(',', ',,')}"]
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

    def screen_text(self):
        """The screen read back as text lines on the 8x16 character grid."""
        return screen_to_text(*self.screendump())

    def wait_screen(self, pattern, timeout=10):
        """Wait until regex `pattern` matches the screen text."""
        rx = re.compile(pattern)
        deadline = time.time() + timeout
        while True:
            text = "\n".join(self.screen_text())
            m = rx.search(text)
            if m:
                return m
            if time.time() > deadline:
                raise TestFailure(f"screen never matched {pattern!r}; screen:\n{text}")
            time.sleep(0.2)

    def sendkeys(self, text, delay=0.03, layout=None):
        layout = layout or ("qwerty" if "kbd=qwerty" in self.cmdline.split() else "azerty")
        for ch in text:
            # QEMU queues keys behind each release, so its 100 ms default
            # hold time would set the typing speed
            self.qmp("send-key", keys=[{"type": "qcode", "data": k} for k in qcodes(ch, layout)],
                     **{"hold-time": 10})
            time.sleep(delay)

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


_glyphs = None


def glyphs():
    """Maps each glyph's 16 row bytes to its character, from build/font.bin."""
    global _glyphs
    if _glyphs is None:
        with open(os.path.join(BUILD, "font.bin"), "rb") as f:
            data = f.read()
        _glyphs = {}
        for i in range(0, len(data), 16):
            # codes without a glyph repeat '?', which comes first
            _glyphs.setdefault(data[i:i + 16], chr(32 + i // 16))
    return _glyphs


def screen_to_text(w, h, px):
    """Reads each 8x16 cell as a glyph. A cell's top-left pixel is background
    (the font leaves row 0 empty), every other colour is ink. Unknown cells
    read as '?'."""
    table = glyphs()
    stride = w * 3
    lines = []
    for cy in range(h // 16):
        line = []
        for cx in range(w // 8):
            base = cy * 16 * stride + cx * 24
            bg = px[base:base + 3]
            rows = bytearray(16)
            for r in range(16):
                row = px[base + r * stride: base + r * stride + 24]
                if row == bg * 8:
                    continue
                bits = 0
                for i in range(8):
                    if row[i * 3:i * 3 + 3] != bg:
                        bits |= 0x80 >> i
                rows[r] = bits
            line.append(table.get(bytes(rows), "?"))
        lines.append("".join(line).rstrip())
    return lines


# QEMU names keys by their US position. Each row lists the qcodes of a run of
# physical keys, then what that run types on each layout (plain, Shift,
# AltGr); "\0" marks no character.
_ROWS = [
    ("1 2 3 4 5 6 7 8 9 0 minus equal",
     {"azerty": ("&é\"'(-è_çà)=", "1234567890°+", "\0~#{[|`\\^@]}"),
      "qwerty": ("1234567890-=", "!@#$%^&*()_+", "")}),
    ("q w e r t y u i o p bracket_left bracket_right",
     {"azerty": ("azertyuiop^$", "AZERTYUIOP¨£", "\0" * 11 + "¤"),
      "qwerty": ("qwertyuiop[]", "QWERTYUIOP{}", "")}),
    ("a s d f g h j k l semicolon apostrophe grave_accent",
     {"azerty": ("qsdfghjklmù²", "QSDFGHJKLM%\0", ""),
      "qwerty": ("asdfghjkl;'`", "ASDFGHJKL:\"~", "")}),
    ("backslash z x c v b n m comma dot slash",
     {"azerty": ("*wxcvbn,;:!", "µWXCVBN?./§", ""),
      "qwerty": ("\\zxcvbnm,./", "|ZXCVBNM<>?", "")}),
    ("less spc ret tab backspace",
     {"azerty": ("< \n\t\b", ">", ""), "qwerty": ("\\ \n\t\b", "|", "")}),
]
_MODS = ([], ["shift"], ["alt_r"])
_KEYMAPS = {}
for names, layouts in _ROWS:
    for layout, levels in layouts.items():
        keymap = _KEYMAPS.setdefault(layout, {})
        for mods, chars in zip(_MODS, levels):
            for name, ch in zip(names.split(), chars):
                if ch != "\0":
                    keymap.setdefault(ch, mods + [name])


def qcodes(ch, layout="azerty"):
    """QMP qcodes that type `ch` on the kernel's keyboard layout."""
    return _KEYMAPS[layout][ch]
