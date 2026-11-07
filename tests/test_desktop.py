import time

from harness import SHELL_READY, TestFailure, Vm
from test_m9_patch import run
from test_mouse import move, pixel

BROWSER = (0x5e, 0x81, 0xac)
DOC = (0x81, 0xa1, 0xc1)
OUTLINE = (0xec, 0xef, 0xf4)
ROWS = 7                                # icons in a column on a 768-row screen
ICONS = ["Terminal", "Browser", "Video", "Glass", "Files", "Monitor", "Reboot", "Shut down",
         "cube.asm", "guess.asm", "hello.asm", "snake.asm", "song.asm", "welcome.txt", "note.txt"]


def corner(name):
    """Top-left pixel of an icon's square."""
    i = ICONS.index(name)
    return 16 + i // ROWS * 112 + 24, 40 + i % ROWS * 104


def point(vm, name):
    x, y = corner(name)
    move(vm, -5000, -5000)
    move(vm, x + 32, y + 32)


def click(vm, button="left"):
    for down in (True, False):
        vm.qmp("input-send-event",
               events=[{"type": "btn", "data": {"down": down, "button": button}}])
        time.sleep(0.1)


def menu(vm, entry):
    """Right-clicks where the pointer is, then clicks the menu's entry-th row."""
    click(vm, "right")
    time.sleep(0.3)
    move(vm, 20, entry * 24 + 12)
    click(vm)


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


def test_desktop_menu_creates_and_deletes_a_file():
    with Vm("desktop_menu") as vm:
        pos = vm.wait_for(SHELL_READY).end()
        vm.sendkeys("desktop\n")
        wait_desktop(vm)
        move(vm, -5000, -5000)
        move(vm, 600, 400)              # empty desktop
        menu(vm, 0)
        vm.wait_screen(r"new file name")
        vm.sendkeys("note.txt\n")
        pos = vm.wait_for(r"\[edit\] note\.txt: opened", start=pos).end()
        vm.sendkeys("hi")
        vm.ctrl("s")
        vm.wait_screen(r"stored, save writes it to disk")
        vm.ctrl("q")
        wait_desktop(vm)
        x, y = corner("note.txt")
        wait_pixel(vm, x + 6, y + 32, DOC)
        point(vm, "note.txt")
        menu(vm, 2)
        vm.sendkeys("y")
        wait_desktop(vm)
        if pixel(vm, x + 6, y + 32) == DOC:
            raise TestFailure("note.txt still has an icon")
        vm.sendkeys("q")
        vm.wait_screen(r"^vitre>")
        out, pos = run(vm, "ls", pos)
        if "note.txt" in out:
            raise TestFailure(f"ls after delete: {out!r}")
