import re

from harness import SHELL_READY, TestFailure, Vm


def run(vm, command, expect, layout=None):
    start = len(vm.serial())
    vm.sendkeys(command + "\n", layout=layout)
    return vm.wait_for(expect + r"[\s\S]*?vitre> ", start=start)


def test_commands():
    with Vm("m7_shell") as vm:
        vm.wait_for(SHELL_READY)
        out = run(vm, "help", r"help +list commands").group(0)
        for name in ("clear", "mem", "tasks", "syms", "uptime", "layout", "reboot"):
            if not re.search(rf"\n  {name} ", out):
                raise TestFailure(f"help does not list {name}")
        run(vm, "mem", r"pages free \d+ of \d+, heap free \d+ of \d+ bytes")
        run(vm, "tasks", r"\[task\] 0 kernel ready")
        run(vm, "syms", r"\[sym\] shell_run [0-9a-f]{16} ")
        run(vm, "uptime", r"up \d+\.\d{3} s")
        run(vm, "  nope  arg", r"unknown command: nope\r\n")
        run(vm, "layout", r"layout azerty\r\n")
        run(vm, "layout qwerty", r"layout qwerty\r\n")
        run(vm, "layout", r"layout qwerty\r\n", layout="qwerty")
        run(vm, "clear", r"", layout="qwerty")
        vm.wait_screen(r"^vitre>\n*$")


def test_history_and_completion():
    with Vm("m7_history") as vm:
        vm.wait_for(SHELL_READY)
        run(vm, "uptime", r"up \d+\.\d{3} s")
        run(vm, "mem", r"pages free")
        run(vm, "mem", r"pages free")             # a repeat is kept once
        start = len(vm.serial())
        vm.press("up")
        vm.press("up")
        vm.press("down")
        vm.press("up")
        vm.sendkeys("\n")
        vm.wait_for(r"up \d+\.\d{3} s\r\nvitre> ", start=start)
        start = len(vm.serial())
        vm.sendkeys("upt")
        vm.press("tab")
        vm.sendkeys("\n")
        vm.wait_for(r"up \d+\.\d{3} s\r\nvitre> ", start=start)
        start = len(vm.serial())
        vm.sendkeys("s")
        vm.press("tab")
        vm.wait_for(r"syms  [\s\S]*shutdown  [\s\S]*\r\nvitre> s", start=start)


def test_reboot():
    with Vm("m7_reboot") as vm:
        vm.wait_for(SHELL_READY)
        vm.sendkeys("reboot\n")
        vm.wait_for(r"\[shell\] rebooting")
        vm.wait_exit()


def test_shutdown():
    with Vm("m7_shutdown") as vm:
        vm.wait_for(SHELL_READY)
        vm.sendkeys("shutdown\n")
        vm.wait_for(r"\[shell\] powering off")
        vm.wait_exit()
