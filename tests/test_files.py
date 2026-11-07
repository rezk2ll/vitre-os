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
