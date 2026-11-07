import hashlib
import random

from harness import SHELL_READY, Vm

QWERTY = "kbd=qwerty"                   # digits without Shift: half the key events


def check(vm, args, want):
    start = len(vm.serial())
    vm.sendkeys(f"crypto {args}\n", delay=0.015)
    got = vm.wait_for(r"\r\n([0-9a-f]*)\r\nvitre> ", start=start, timeout=30).group(1)
    assert got == want, f"crypto {args}: got {got}, want {want}"


def test_sha256_vectors():
    rng = random.Random(15)
    # FIPS 180-4 examples, then lengths around the block and padding edges
    inputs = [b"", b"abc", b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"]
    with Vm("m15_sha256", cmdline=QWERTY) as vm:
        vm.wait_for(SHELL_READY)
        for data in inputs + [rng.randbytes(n) for n in (1, 55, 56, 63, 64, 65, 119, 120, 128)]:
            check(vm, f"sha256 {data.hex()}", hashlib.sha256(data).hexdigest())
