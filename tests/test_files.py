import os
import re

from harness import SHELL_READY, TestFailure, Vm, fresh_disk
from test_m9_patch import run


def write_file(vm, name, text, pos):
    """Creates a file in the editor, types the text and stores it."""
    vm.sendkeys(f"edit {name}\n")
    pos = vm.wait_for(rf"\[edit\] {re.escape(name)}: opened", start=pos).end()
    vm.sendkeys(text)
    vm.ctrl("s")
    pos = vm.wait_for(rf"\[edit\] {re.escape(name)}: stored {len(text)} bytes", start=pos).end()
    vm.wait_screen(r"stored, save writes it to disk")
    vm.ctrl("q")
    return vm.wait_for(r"\r\nvitre> ", start=pos).end()


def test_ls_cat_edit_rm():
    with Vm("files") as vm:
        pos = vm.wait_for(SHELL_READY).end()
        out, pos = run(vm, "ls", pos)
        if not re.search(r"kernel/report\.asm +\d+ bytes, kernel module", out):
            raise TestFailure(f"ls: {out!r}")
        if not re.search(r"welcome\.txt +\d+ bytes$", out):
            raise TestFailure(f"ls: {out!r}")
        out, pos = run(vm, "cat welcome.txt", pos)
        if "Welcome to Vitre." not in out:
            raise TestFailure(f"cat: {out!r}")
        pos = write_file(vm, "notes.txt", "first line\nsecond", pos)
        out, pos = run(vm, "cat notes.txt", pos)
        if out != "first line\r\nsecond":
            raise TestFailure(f"cat notes.txt: {out!r}")
        out, pos = run(vm, "rm kernel/report.asm", pos)
        if "not a user file: kernel/report.asm" not in out:
            raise TestFailure(f"rm of a module: {out!r}")
        out, pos = run(vm, "rm notes.txt", pos)
        if "removed notes.txt" not in out:
            raise TestFailure(f"rm: {out!r}")
        out, pos = run(vm, "ls", pos)
        if "notes.txt" in out or "welcome.txt" not in out:
            raise TestFailure(f"ls after rm: {out!r}")
        out, pos = run(vm, "forge", pos)
        if "welcome.txt" in out or not re.search(r"same as the kernel", out):
            raise TestFailure(f"forge: {out!r}")


def test_tab_completes_file_names():
    with Vm("files_tab") as vm:
        pos = vm.wait_for(SHELL_READY).end()
        vm.sendkeys("cat wel")
        vm.press("tab")
        vm.sendkeys("\n")
        pos = vm.wait_for(r"cat welcome\.txt\r\nWelcome to Vitre\.", start=pos).end()
        vm.sendkeys("run ")
        vm.press("tab")
        pos = vm.wait_for(r"kernel/report\.asm  cube\.asm  guess\.asm  hello\.asm  snake\.asm"
                          r"  welcome\.txt  \r\nvitre> run ", start=pos).end()
        vm.sendkeys("sn")
        vm.press("tab")
        vm.sendkeys(" x")
        vm.wait_for(r"snake\.asm x", start=pos)


def test_saved_file_survives_reboot():
    disk = fresh_disk()
    try:
        with Vm("files_save", disk=disk) as vm:
            pos = vm.wait_for(SHELL_READY).end()
            pos = write_file(vm, "todo.txt", "buy milk", pos)
            out, pos = run(vm, "save", pos)
            vm.sendkeys("reboot\n")
            vm.wait_exit()
        with Vm("files_saved", disk=disk) as vm:
            pos = vm.wait_for(SHELL_READY).end()
            if "[patch]" in vm.serial():
                raise TestFailure("boot patched a user file")
            out, pos = run(vm, "cat todo.txt", pos)
            if out != "buy milk":
                raise TestFailure(f"cat after reboot: {out!r}")
    finally:
        os.remove(disk)


def listed(vm):
    """The file names the file manager shows, top to bottom."""
    return [m.group(1) for m in (re.match(r" (\S+) +\d+ bytes", line)
                                 for line in vm.screen_text()) if m]


def select(vm, name):
    for _ in range(len(listed(vm))):
        vm.press("up")
    for _ in range(listed(vm).index(name)):
        vm.press("down")


def test_file_manager():
    with Vm("fileman") as vm:
        pos = vm.wait_for(SHELL_READY).end()
        vm.sendkeys("files\n")
        vm.wait_screen(r"Vitre files")
        vm.wait_screen(r"kernel/report\.asm +\d+ bytes, kernel module")
        names = listed(vm)
        if not {"hello.asm", "welcome.txt"} <= set(names):
            raise TestFailure(f"listed: {names}")
        select(vm, "hello.asm")
        vm.sendkeys("r")
        vm.wait_screen(r"Hello, world!")
        vm.sendkeys(" ")
        vm.wait_screen(r"Vitre files")
        select(vm, "welcome.txt")
        vm.sendkeys("r")
        vm.wait_screen(r"only \.asm files run")
        vm.sendkeys("n")
        vm.wait_screen(r"new file name")
        vm.sendkeys("note.txt\n")
        vm.wait_for(r"\[edit\] note\.txt: opened", start=pos)
        vm.sendkeys("hi")
        vm.ctrl("s")
        vm.wait_screen(r"stored, save writes it to disk")
        vm.ctrl("q")
        vm.wait_screen(r"note\.txt +2 bytes")
        select(vm, "note.txt")
        vm.sendkeys("d")
        vm.wait_screen(r"delete this file\?")
        vm.sendkeys("y")
        vm.wait_screen(r"removed")
        if "note.txt" in listed(vm):
            raise TestFailure(f"after delete: {listed(vm)}")
        select(vm, "kernel/report.asm")
        vm.sendkeys("d")
        vm.wait_screen(r"kernel modules cannot be deleted")
        vm.sendkeys("q")
        vm.wait_screen(r"^vitre>")
