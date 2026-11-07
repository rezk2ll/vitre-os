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


def test_e1000_comes_up():
    with Vm("m11_e1000", net=True) as vm:
        vm.wait_for(r"\[net\] e1000 mac 52:54:00:12:34:56 irq \d+")
        vm.wait_for(SHELL_READY)
        run(vm, "net", r"\[net\] mac 52:54:00:12:34:56, link up, rx \d+ frames, tx 0")


def test_no_card_is_reported():
    with Vm("m11_no_net") as vm:
        vm.wait_for(r"\[net\] no network card")


def test_arp_resolves_the_gateway():
    with Vm("m11_arp", net=True) as vm:
        vm.wait_for(SHELL_READY)
        run(vm, "arp 10.0.2.2", r"\[arp\] 10\.0\.2\.2 is 52:55:0a:00:02:02")
        run(vm, "arp", r"\[arp\] 10\.0\.2\.2 is 52:55:0a:00:02:02")
        run(vm, "arp 10.0.2.300", r"usage: arp")
