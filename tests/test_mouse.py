import time

from harness import SHELL_READY, TestFailure, Vm
from test_m7_shell import run


def move(vm, dx, dy, *buttons):
    # QEMU's PS/2 queue holds a few packets per event and drains the rest of
    # a large move later, into the next one, so large moves go in steps
    steps = max(1, (max(abs(dx), abs(dy)) + 99) // 100)
    for i in range(steps):
        sx = dx * (i + 1) // steps - dx * i // steps
        sy = dy * (i + 1) // steps - dy * i // steps
        vm.qmp("input-send-event", events=[{"type": "rel", "data": {"axis": "x", "value": sx}},
                                           {"type": "rel", "data": {"axis": "y", "value": sy}}])
        time.sleep(0.01)
    if buttons:
        vm.qmp("input-send-event", events=[
            {"type": "btn", "data": {"down": True, "button": b}} for b in buttons])
    time.sleep(0.2)


def test_mouse_moves_and_clicks():
    with Vm("mouse") as vm:
        vm.wait_for(SHELL_READY)
        run(vm, "mouse", r"mouse 512 384 buttons 0\r\n")
        move(vm, 40, -30)
        run(vm, "mouse", r"mouse 552 354 buttons 0\r\n")
        move(vm, -5000, 5000, "left")
        run(vm, "mouse", r"mouse 0 767 buttons 1\r\n")


def pixel(vm, x, y):
    w, _, rgb = vm.screendump()
    i = (y * w + x) * 3
    return tuple(rgb[i:i + 3])


def test_pointer_follows_the_mouse():
    with Vm("cursor") as vm:
        vm.wait_for(SHELL_READY)
        if pixel(vm, 513, 390) == (255, 255, 255):
            raise TestFailure("the pointer shows before the mouse moved")
        move(vm, 100, 0)
        if pixel(vm, 612, 384) != (0, 0, 0) or pixel(vm, 613, 390) != (255, 255, 255):
            raise TestFailure("no pointer drawn at 612,384")
        move(vm, 0, 100)
        if pixel(vm, 613, 390) == (255, 255, 255):
            raise TestFailure("the pointer left its old place drawn")
        if pixel(vm, 612, 484) != (0, 0, 0):
            raise TestFailure("no pointer drawn at 612,484")
        run(vm, "help", r"mouse")


def wheel(vm, way, notches):
    for _ in range(notches):
        for down in (True, False):
            vm.qmp("input-send-event",
                   events=[{"type": "btn", "data": {"down": down, "button": way}}])


def test_editor_follows_clicks_and_the_wheel():
    with Vm("editor_mouse") as vm:
        vm.wait_for(SHELL_READY)
        vm.sendkeys("edit kernel/report.asm\n")
        vm.wait_screen(r"; Log printers[\s\S]*\n; name: kput_dec")
        move(vm, -5000, -5000)
        move(vm, 2 * 8 + 4, 3 * 16 + 8)           # the "n" of "; name: kput_dec"
        for down in (True, False):
            vm.qmp("input-send-event",
                   events=[{"type": "btn", "data": {"down": down, "button": "left"}}])
        move(vm, 900, 500)                        # off the text, so it reads cleanly
        vm.sendkeys("X")
        vm.wait_screen(r"\n; Xname: kput_dec")
        wheel(vm, "wheel-down", 20)
        deadline = time.time() + 10
        while "Log printers" in vm.screen_text():
            if time.time() > deadline:
                raise TestFailure("the wheel did not scroll the editor")
            time.sleep(0.2)
        wheel(vm, "wheel-up", 20)                 # back to the edited line, on top
        vm.wait_screen(r"\A; Xname: kput_dec")
