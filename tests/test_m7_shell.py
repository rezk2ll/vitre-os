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
        for name in ("clear", "mem", "tasks", "syms"):
            if not re.search(rf"\n  {name} ", out):
                raise TestFailure(f"help does not list {name}")
        run(vm, "mem", r"pages free \d+ of \d+, heap free \d+ of \d+ bytes")
        run(vm, "tasks", r"\[task\] 0 kernel ready")
        run(vm, "syms", r"\[sym\] shell_run [0-9a-f]{16} ")
        run(vm, "  nope  arg", r"unknown command: nope\r\n")
        run(vm, "clear", r"")
        vm.wait_screen(r"^vitre>\n*$")
