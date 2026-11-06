from harness import TestFailure, Vm


def test_framebuffer_mode():
    with Vm("m3_mode") as vm:
        vm.wait_for(r"\[boot\] vbe mode set")
        vm.wait_for(r"\[fb\] 1024x768\r\n")
        w, h, _ = vm.screendump()
        if (w, h) != (1024, 768):
            raise TestFailure(f"screen is {w}x{h}, expected 1024x768")
