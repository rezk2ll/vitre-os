import time

from harness import SHELL_READY, Vm
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
