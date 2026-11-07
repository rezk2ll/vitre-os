import time

from harness import SHELL_READY, TestFailure, Vm
from test_mouse import move, pixel

BROWSER = (0x5e, 0x81, 0xac)
OUTLINE = (0xec, 0xef, 0xf4)
ROWS = 7                                # icons in a column on a 768-row screen
ICONS = ["Terminal", "Browser", "Glass", "Files", "Monitor", "Reboot", "Shut down",
         "cube.asm", "guess.asm", "hello.asm", "snake.asm", "welcome.txt"]


def corner(name):
    """Top-left pixel of an icon's square."""
    i = ICONS.index(name)
    return 16 + i // ROWS * 112 + 24, 40 + i % ROWS * 104


def point(vm, name):
    x, y = corner(name)
    move(vm, -5000, -5000)
    move(vm, x + 32, y + 32)


def click(vm):
    for down in (True, False):
        vm.qmp("input-send-event",
               events=[{"type": "btn", "data": {"down": down, "button": "left"}}])
        time.sleep(0.1)


def open_icon(vm, name):
    point(vm, name)
    click(vm)


def wait_pixel(vm, x, y, rgb, timeout=10):
    deadline = time.time() + timeout
    while pixel(vm, x, y) != rgb:
        if time.time() > deadline:
            raise TestFailure(f"{x},{y} is {pixel(vm, x, y)}, not {rgb}")
        time.sleep(0.2)


def wait_desktop(vm):
    x, y = corner("Browser")
    wait_pixel(vm, x + 6, y + 32, BROWSER)


def test_desktop_opens_apps_and_files():
    with Vm("desktop", net=True) as vm:
        pos = vm.wait_for(SHELL_READY).end()
        vm.sendkeys("desktop\n")
        wait_desktop(vm)
        x, y = corner("Browser")
        point(vm, "Browser")
        wait_pixel(vm, x + 1, y + 1, OUTLINE)
        move(vm, 200, 0)                # off every icon
        wait_pixel(vm, x + 1, y + 1, BROWSER)
        open_icon(vm, "Browser")
        vm.wait_screen(r"Vitre browser")
        vm.sendkeys("q")
        wait_desktop(vm)
        open_icon(vm, "Files")
        vm.wait_screen(r"Vitre files")
        vm.sendkeys("q")
        wait_desktop(vm)
        open_icon(vm, "hello.asm")
        vm.wait_screen(r"Hello, world!")
        vm.wait_screen(r"press a key or click to go back")
        vm.sendkeys(" ")
        wait_desktop(vm)
        open_icon(vm, "welcome.txt")
        pos = vm.wait_for(r"\[edit\] welcome\.txt: opened", start=pos).end()
        vm.ctrl("q")
        wait_desktop(vm)
        open_icon(vm, "Terminal")
        vm.wait_for(r"vitre> ", start=pos)
        vm.wait_screen(r"^vitre>")
