import hashlib
import hmac
import random
import struct

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


def chacha20(key, nonce, counter, data):
    def qr(x, a, b, c, d):
        for p, q, r, s in ((a, b, d, 16), (c, d, b, 12), (a, b, d, 8), (c, d, b, 7)):
            x[p] = (x[p] + x[q]) & 0xffffffff
            x[r] ^= x[p]
            x[r] = (x[r] << s | x[r] >> (32 - s)) & 0xffffffff
    out = b""
    for i in range(0, len(data), 64):
        state = list(struct.unpack("<16I", b"expand 32-byte k" + key
                                   + struct.pack("<I", counter + i // 64) + nonce))
        x = state[:]
        for _ in range(10):
            for q in ((0, 4, 8, 12), (1, 5, 9, 13), (2, 6, 10, 14), (3, 7, 11, 15),
                      (0, 5, 10, 15), (1, 6, 11, 12), (2, 7, 8, 13), (3, 4, 9, 14)):
                qr(x, *q)
        stream = struct.pack("<16I", *((a + b) & 0xffffffff for a, b in zip(x, state)))
        out += bytes(a ^ b for a, b in zip(data[i:i + 64], stream))
    return out


def test_chacha20_vectors():
    rng = random.Random(8439)
    sunscreen = (b"Ladies and Gentlemen of the class of '99: If I could offer you only one tip "
                 b"for the future, sunscreen would be it.")
    # RFC 8439 2.4.2 and A.2 #1, then random keys over block edges
    cases = [(bytes(range(32)), bytes(7) + b"\x4a" + bytes(4), 1, sunscreen),
             (bytes(32), bytes(12), 0, bytes(64))]
    assert chacha20(*cases[0]).hex().startswith("6e2e359a2568f98041ba0728dd0d6981")
    assert chacha20(*cases[1]).hex().startswith("76b8e0ada0f13d90405d6ae55386bd28")
    cases += [(rng.randbytes(32), rng.randbytes(12), rng.randrange(256), rng.randbytes(n))
              for n in (1, 63, 64, 65, 200)]
    with Vm("m15_chacha20", cmdline=QWERTY) as vm:
        vm.wait_for(SHELL_READY)
        for key, nonce, counter, data in cases:
            check(vm, f"chacha20 {key.hex()} {nonce.hex()} {counter:02x} {data.hex()}",
                  chacha20(key, nonce, counter, data).hex())
