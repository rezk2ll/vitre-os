import re

from harness import TestFailure, Vm


def test_keystrokes_echo():
    with Vm("m3_keys") as vm:
        m = vm.wait_for(r"\[kbd\] echo ready\r\n")
        typed = "Hello, Vitre! {a-z} 0123456789"
        vm.sendkeys(typed + "\n")
        vm.wait_for(re.escape(typed) + r"\r\n", start=m.end())
        vm.wait_screen(r"\n" + re.escape(typed) + r"\n")


def test_backspace_erases():
    with Vm("m3_backspace") as vm:
        vm.wait_for(r"\[kbd\] echo ready")
        vm.sendkeys("abcx\bd\n")
        vm.wait_screen(r"\nabcd\n")


def test_console_scrolls():
    with Vm("m3_scroll") as vm:
        vm.wait_for(r"\[kbd\] echo ready")
        vm.sendkeys("top\n" + "\n" * 50 + "bottom", delay=0.01)
        vm.wait_screen(r"bottom$")
        lines = vm.screen_text()
        if lines[-1] != "bottom" or "top" in lines:
            raise TestFailure(f"unexpected screen after scrolling: {lines[-3:]}")
