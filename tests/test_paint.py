import time

from harness import SHELL_READY, TestFailure, Vm
from test_desktop import corner, point, wait_desktop, wait_pixel
from test_mouse import move, pixel

PAPER = (0xff, 0xff, 0xff)
BLACK = (0, 0, 0)
RED = (0xbf, 0x61, 0x6a)


def button(vm, name, down):
    vm.qmp("input-send-event", events=[{"type": "btn", "data": {"down": down, "button": name}}])
    time.sleep(0.1)


def drag(vm, dx, dy, name="left"):
    button(vm, name, True)
    move(vm, dx, dy)
    button(vm, name, False)


def to(vm, x, y):
    move(vm, -5000, -5000)
    move(vm, x, y)


def test_paint_draws_picks_colours_and_rubs_out():
    with Vm("paint") as vm:
        vm.wait_for(SHELL_READY)
        vm.sendkeys("paint\n")
        wait_pixel(vm, 500, 500, PAPER)
        to(vm, 300, 300)
        drag(vm, 100, 0)
        wait_pixel(vm, 350, 300, BLACK)
        to(vm, 44, 12)                  # the second swatch
        button(vm, "left", True)
        button(vm, "left", False)
        to(vm, 300, 400)
        drag(vm, 100, 0)
        wait_pixel(vm, 350, 400, RED)
        to(vm, 350, 280)
        drag(vm, 0, 40, "right")
        wait_pixel(vm, 350, 300, PAPER)
        if pixel(vm, 330, 300) != BLACK:
            raise TestFailure("rubbing out took more than the brush")
        vm.sendkeys("q")
        vm.wait_screen(r"^vitre>")


def test_the_click_that_opens_paint_does_not_draw():
    with Vm("paint_icon") as vm:
        vm.wait_for(SHELL_READY)
        vm.sendkeys("desktop\n")
        wait_desktop(vm)
        point(vm, "Paint")
        button(vm, "left", True)
        wait_pixel(vm, 500, 500, PAPER)
        button(vm, "left", False)
        x, y = corner("Paint")
        time.sleep(0.5)
        if pixel(vm, x + 30, y + 34) != PAPER:
            raise TestFailure("the click on the icon left a dab")
