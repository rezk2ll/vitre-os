import time

from harness import SHELL_READY, TestFailure, Vm
from test_mouse import move, pixel

BROWSER_TILE = (0x5e, 0x81, 0xac)
OUTLINE = (0xec, 0xef, 0xf4)
SNAKE_BG = (0x2e, 0x34, 0x40)


def click(vm):
    for down in (True, False):
        vm.qmp("input-send-event",
               events=[{"type": "btn", "data": {"down": down, "button": "left"}}])
        time.sleep(0.1)


def wait_pixel(vm, x, y, rgb, timeout=10):
    deadline = time.time() + timeout
    while pixel(vm, x, y) != rgb:
        if time.time() > deadline:
            raise TestFailure(f"{x},{y} is {pixel(vm, x, y)}, not {rgb}")
        time.sleep(0.2)


def test_desktop_opens_apps():
    with Vm("desktop", net=True) as vm:
        pos = vm.wait_for(SHELL_READY).end()
        vm.sendkeys("desktop\n")
        wait_pixel(vm, 420, 230, BROWSER_TILE)
        move(vm, -110, -90)             # onto the Browser tile
        wait_pixel(vm, 420, 225, OUTLINE)
        move(vm, 0, 100)                # into the gap below it
        wait_pixel(vm, 420, 225, BROWSER_TILE)
        move(vm, 0, -100)
        click(vm)
        vm.wait_screen(r"Vitre browser")
        vm.sendkeys("q")
        wait_pixel(vm, 420, 230, BROWSER_TILE)
        vm.sendkeys("6")                # Snake
        wait_pixel(vm, 420, 230, SNAKE_BG)
        vm.sendkeys("q")
        wait_pixel(vm, 420, 230, BROWSER_TILE)
        vm.sendkeys("1")                # Terminal
        vm.wait_for(r"vitre> ", start=pos)
        vm.wait_screen(r"^vitre>")
