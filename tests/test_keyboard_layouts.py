import re

from harness import SHELL_READY, Vm

FRENCH = "Bonjour à tous, ça marche! é è ù µ £ § ° ² {[|`\\^@]} ~# <>"


def test_azerty_is_default():
    with Vm("kbd_azerty") as vm:
        m = vm.wait_for(SHELL_READY)
        vm.sendkeys(FRENCH + "\n")
        vm.wait_for(re.escape(FRENCH) + r"\r\n", start=m.end())
        vm.wait_screen(r"\nvitre> " + re.escape(FRENCH) + r"\n")


def test_qwerty_option():
    with Vm("kbd_qwerty", cmdline="kbd=qwerty") as vm:
        m = vm.wait_for(SHELL_READY)
        typed = "qwerty QWERTY [];'\\,./ {}:\"|<>?"
        vm.sendkeys(typed + "\n")
        vm.wait_for(re.escape(typed) + r"\r\n", start=m.end())
