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
