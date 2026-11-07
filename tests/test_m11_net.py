import re

from harness import SHELL_READY, TestFailure, Vm


def run(vm, command, expect):
    start = len(vm.serial())
    vm.sendkeys(command + "\n")
    return vm.wait_for(expect + r"[\s\S]*?vitre> ", start=start)


def test_lspci_finds_the_e1000():
    with Vm("m11_lspci", net=True) as vm:
        vm.wait_for(SHELL_READY)
        out = run(vm, "lspci", r"00:00\.0 8086:1237").group(0)
        if not re.search(r"00:0[0-9a-f]\.0 8086:100e class 02\.00 irq \d+", out):
            raise TestFailure(f"no e1000 in lspci: {out!r}")
