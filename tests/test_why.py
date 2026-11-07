import re
import time

from harness import SHELL_READY, TestFailure, Vm
from test_mouse import move, pixel


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


def test_f12_inspects_the_clicked_pixel():
    with Vm("inspect") as vm:
        vm.wait_for(SHELL_READY)
        vm.sendkeys("mem\n")
        vm.wait_screen(r"pages free")
        row = next(i for i, line in enumerate(vm.screen_text()) if "pages free" in line)
        y = row * 16 + 8
        words = pixel(vm, 2 * 8 + 3, row * 16 + 6)     # ink of the 'g' in "pages"
        vm.press("f12")
        vm.wait_screen(r"\AInspect: click any pixel")
        move(vm, -5000, -5000)
        move(vm, 4, y, "left")
        vm.wait_screen(r"drawn by task 0 kernel.*\n.* console_putc\+\d+.*\n.* kputc\+\d+.*\n"
                       r".* kputs\+\d+.*\n.* cmd_mem\+\d+")
        if pixel(vm, 2 * 8 + 3, row * 16 + 6) != words:
            raise TestFailure("the clicked text did not keep its colour")
        vm.press("esc")
        vm.wait_screen(r"ges free \d+ of")            # the pointer covers "pa"
        time.sleep(0.3)
        if any("drawn by" in line or "Inspect" in line for line in vm.screen_text()):
            raise TestFailure("inspect mode left its drawing behind")
