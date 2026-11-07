from harness import SHELL_READY, Vm
from test_m7_shell import run


def test_date_reads_the_clock():
    with Vm("rtc", extra=["-rtc", "base=2031-02-28T23:59:30"]) as vm:
        vm.wait_for(SHELL_READY)
        run(vm, "date", r"2031-02-28 23:59:[34]\d UTC\r\n")
