import os
import struct
import tempfile

from harness import SHELL_READY, TestFailure, Vm


def pitch(path):
    """The rate and the pitch of the left channel of a 16-bit stereo wav,
    counted from its sign changes."""
    data = open(path, "rb").read()
    rate = struct.unpack_from("<I", data, 24)[0]
    samples = data[data.index(b"data") + 8:]
    left = struct.unpack_from(f"<{len(samples) // 4 * 2}h", samples)[::2]
    sound = [s for s in left if abs(s) > 1000]
    flips = sum(1 for a, b in zip(sound, sound[1:]) if (a < 0) != (b < 0))
    return rate, flips / 2 / (len(sound) / rate) if sound else 0


def dropouts(path):
    """The seconds from the first loud sample to the last, and how many
    runs of silence longer than a millisecond break it."""
    data = open(path, "rb").read()
    rate = struct.unpack_from("<I", data, 24)[0]
    samples = data[data.index(b"data") + 8:]
    left = struct.unpack_from(f"<{len(samples) // 4 * 2}h", samples)[::2]
    loud = [i for i, s in enumerate(left) if abs(s) > 3000]
    run, gaps = 0, 0
    for s in left[loud[0]:loud[-1]]:
        if abs(s) < 300:
            run += 1
        else:
            gaps += run > rate // 1000
            run = 0
    return (loud[-1] - loud[0]) / rate, gaps


def test_beep_plays_a_tone():
    wav = os.path.join(tempfile.mkdtemp(prefix="vitre-snd-"), "out.wav")
    with Vm("beep", extra=["-audiodev", f"wav,id=snd,path={wav}",
                           "-device", "AC97,audiodev=snd"]) as vm:
        pos = vm.wait_for(r"\[sound\] ac97 ready").end()
        pos = vm.wait_for(SHELL_READY, start=pos).end()
        vm.sendkeys("beep 880\n")
        pos = vm.wait_for(r"vitre> ", start=pos, timeout=10).end()
        vm.sendkeys("beep 5\n")
        vm.wait_for(r"usage: beep \[hz\]", start=pos)
        vm.qmp("quit")
        vm.proc.wait(timeout=10)
    rate, hz = pitch(wav)
    if not 850 < hz < 920:                  # a half period is a whole number of frames
        raise TestFailure(f"heard {hz:.0f} Hz at {rate} Hz, not 880")


def test_beep_without_a_card():
    with Vm("beep_none") as vm:
        pos = vm.wait_for(SHELL_READY).end()
        vm.sendkeys("beep\n")
        vm.wait_for(r"\[beep\] no sound card", start=pos)
