import random

from harness import SHELL_READY, Vm
from test_m15_crypto import QWERTY, check

P = 2**256 - 2**224 + 2**192 + 2**96 - 1
N = 0xffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551


def be(x):
    return x.to_bytes(32, "big").hex()


def test_p256_field_and_order():
    rng = random.Random(256)
    edges = [1, P - 1, P - 2, 2**255]
    pairs = [(a, b) for a in edges for b in (P - 1, 2**200 + 3)]
    pairs += [(rng.randrange(P), rng.randrange(P)) for _ in range(3)]
    inverses = [1, N - 1, N - 2] + [rng.randrange(1, N) for _ in range(2)]
    with Vm("m17_mont", cmdline=QWERTY) as vm:
        vm.wait_for(SHELL_READY)
        for a, b in pairs:
            check(vm, f"pmul {be(a)} {be(b)}", be(a * b % P))
        for a in inverses:
            check(vm, f"ninv {be(a)}", be(pow(a, -1, N)))


G = (0x6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296,
     0x4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5)


def add(a, b):
    if a is None:
        return b
    if b is None:
        return a
    if a[0] == b[0] and (a[1] + b[1]) % P == 0:
        return None
    if a == b:
        m = (3 * a[0] * a[0] - 3) * pow(2 * a[1], -1, P)
    else:
        m = (b[1] - a[1]) * pow(b[0] - a[0], -1, P)
    x = (m * m - a[0] - b[0]) % P
    return x, (m * (a[0] - x) - a[1]) % P


def mul(k, pt):
    out = None
    while k:
        if k & 1:
            out = add(out, pt)
        pt, k = add(pt, pt), k >> 1
    return out


def test_p256_point_multiply():
    rng = random.Random(2001)
    q = mul(rng.randrange(1, N), G)
    cases = [(k, G) for k in (1, 2, 3, N - 1, rng.randrange(N))]
    cases += [(k, q) for k in (1, rng.randrange(N))]
    with Vm("m17_ecmul", cmdline=QWERTY) as vm:
        vm.wait_for(SHELL_READY)
        for k, pt in cases:
            check(vm, f"ecmul {be(k)} {be(pt[0])}{be(pt[1])}", be(mul(k, pt)[0]))
        check(vm, f"ecmul {be(N)} {be(G[0])}{be(G[1])}", "")
