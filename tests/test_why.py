import re

from harness import SHELL_READY, TestFailure, Vm


def test_why_names_the_chain_that_drew_a_pixel():
    with Vm("why") as vm:
        vm.wait_for(SHELL_READY)
        vm.sendkeys("mem\n")
        vm.wait_screen(r"pages free")
        row = next(i for i, line in enumerate(vm.screen_text()) if "pages free" in line)
        start = len(vm.serial())
        vm.sendkeys(f"why 4 {row * 16 + 8}\n")
        out = vm.wait_for(r"\[why\] task[\s\S]*?vitre> ", start=start).group(0)
        frames = re.findall(r"\[why\]   [0-9a-f]{16} (\w+)\+\d+", out)
        if frames[:4] != ["console_putc", "kputc", "kputs", "cmd_mem"]:
            raise TestFailure(f"chain: {frames}")
        if "shell_execute" not in frames or not out.startswith("[why] task 0 kernel"):
            raise TestFailure(out)
        start = len(vm.serial())
        vm.sendkeys("why 5000 1\n")
        vm.wait_for(r"usage: why <x> <y>", start=start)
