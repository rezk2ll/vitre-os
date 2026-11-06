from harness import TestFailure, Vm, glyphs


def test_font_glyphs_are_distinct():
    if len(glyphs()) != 95:
        raise TestFailure(f"{95 - len(glyphs())} glyphs share a bitmap with another")


def test_boot_log_on_screen():
    with Vm("m3_screen") as vm:
        vm.wait_for(r"\[kernel\] interrupts on")
        vm.wait_screen(r"\[boot\] long mode ok\n\[fb\] 1024x768\n")
        vm.wait_screen(r"\[kernel\] interrupts on")
