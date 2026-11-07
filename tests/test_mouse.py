import time

from harness import SHELL_READY, TestFailure, Vm
from test_m7_shell import run


def move(vm, dx, dy, *buttons):
    events = [{"type": "rel", "data": {"axis": "x", "value": dx}},
              {"type": "rel", "data": {"axis": "y", "value": dy}}]
    events += [{"type": "btn", "data": {"down": True, "button": b}} for b in buttons]
    vm.qmp("input-send-event", events=events)
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
