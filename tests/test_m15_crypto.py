import hashlib
import hmac
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
            check(vm, f"sha256 {hx(data)}", hashlib.sha256(data).hexdigest())


def hkdf(salt, key, info, n):
    prk = hmac.digest(salt, key, "sha256")
    okm, t = b"", b""
    for i in range(1, -(-n // 32) + 1):
        t = hmac.digest(prk, t + info + bytes([i]), "sha256")
        okm += t
    return okm[:n]


def hx(data):
    return data.hex() or "-"


def test_hmac_and_hkdf_vectors():
    # RFC 4231 cases 1, 2, 3, 4, 6 and 7: short, long (hashed) and odd keys
    macs = [(b"\x0b" * 20, b"Hi There"), (b"Jefe", b"what do ya want for nothing?"),
            (b"\xaa" * 20, b"\xdd" * 50), (bytes(range(1, 26)), b"\xcd" * 50),
            (b"\xaa" * 131, b"Test Using Larger Than Block-Size Key - Hash Key First"),
            (b"\xaa" * 131, b"This is a test using a larger than block-size key and a larger than "
             b"block-size data. The key needs to be hashed before being used by the HMAC algorithm.")]
    # RFC 5869 cases 1 to 3: a short info, a three-block output, empty salt and info
    kdfs = [(bytes(range(13)), b"\x0b" * 22, bytes(range(0xf0, 0xfa)), 42),
            (bytes(range(0x60, 0xb0)), bytes(range(0x50)), bytes(range(0xb0, 0x100)), 82),
            (b"", b"\x0b" * 22, b"", 42)]
    assert hkdf(*kdfs[0]).hex().startswith("3cb25f25faacd57a90434f64d0362f2a")
    with Vm("m15_hkdf", cmdline=QWERTY) as vm:
        vm.wait_for(SHELL_READY)
        for key, msg in macs:
            check(vm, f"hmac {hx(key)} {hx(msg)}", hmac.digest(key, msg, "sha256").hex())
        for salt, key, info, n in kdfs:
            check(vm, f"hkdf {hx(salt)} {hx(key)} {hx(info)} {n:02x}", hkdf(salt, key, info, n).hex())
