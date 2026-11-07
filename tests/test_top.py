import re

from harness import SHELL_READY, Vm


def test_top_shows_memory_and_tasks_live():
    with Vm("top") as vm:
        pos = vm.wait_for(SHELL_READY).end()
        vm.sendkeys("top\n")
        m = vm.wait_screen(r"Vitre monitor[\s\S]*uptime +(\d+) s[\s\S]*"
                           r"memory +\[[#.]{40}\] +\d+ of \d+ pages used[\s\S]*"
                           r"heap +\[[#.]{40}\] +\d+ of \d+ bytes used[\s\S]*"
                           r"\n 0 +kernel +ready +\d+")
        seconds = int(m.group(1))
        vm.wait_screen(rf"uptime +({seconds + 1}|{seconds + 2}) s")
        vm.sendkeys("q")
        vm.wait_for(r"\r\nvitre> ", start=pos)
        vm.wait_screen(r"^vitre>")
