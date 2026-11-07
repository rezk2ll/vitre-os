import struct
import subprocess
import tempfile

from harness import TestFailure

VIVENC = "build/vivenc"


def encode(frames, w, h, fps=10, chunk=None, sound=None):
    args = [VIVENC, str(w), str(h), str(fps)] + ([str(chunk)] if chunk else [])
    if sound is None:
        return subprocess.run(args, input=b"".join(frames), capture_output=True, check=True).stdout
    with tempfile.NamedTemporaryFile() as f:
        f.write(sound)
        f.flush()
        return subprocess.run(["sh", "-c", 'exec "$@" 3<"$SOUND"', "sh"] + args,
                              env={"SOUND": f.name}, input=b"".join(frames),
                              capture_output=True, check=True).stdout


def decode(data):
    """The header, then the frames of a .viv file, each a bytes of one byte
    per pixel, then each frame's sound samples."""
    if data[:4] != b"VIV1":
        raise TestFailure(f"magic: {data[:4]!r}")
    w, h, fps, rate, chunk = struct.unpack_from("<HHHHI", data, 4)
    frame, frames, sounds = bytearray(w * h), [], []
    for start in range(0, len(data), chunk):
        pos, end = start + (16 if start == 0 else 0), min(start + chunk, len(data))
        while pos + 4 <= end:
            (n,) = struct.unpack_from("<I", data, pos)
            if n == 0:
                break
            pos += 4
            if rate:
                (k,) = struct.unpack_from("<H", data, pos)
                sounds.append(data[pos + 2:pos + 2 + k])
                pos += 2 + k
            codes, pos, px = data[pos:pos + n], pos + n, 0
            i = 0
            while i < len(codes):
                op, count = codes[i] >> 6, (codes[i] & 63) + 1
                if op == 1:
                    frame[px:px + count] = bytes([codes[i + 1]]) * count
                    i += 2
                elif op == 2:
                    frame[px:px + count] = codes[i + 1:i + 1 + count]
                    i += 1 + count
                else:
                    i += 1
                px += count
            if px != w * h:
                raise TestFailure(f"frame {len(frames)} covers {px} pixels, not {w * h}")
            frames.append(bytes(frame))
    return (w, h, fps, rate, chunk), frames, sounds


def test_vivenc_round_trip():
    w, h = 40, 30
    red, blue = bytes((255, 0, 0)) * (w * h), bytes((0, 0, 255)) * (w * h)
    moving = []
    for k in range(20):
        rgb = bytearray(blue)
        for y in range(10, 20):
            for x in range(k, k + 10):
                rgb[(y * w + x) * 3:(y * w + x) * 3 + 3] = (255, 255, 0)
        moving.append(bytes(rgb))
    data = encode([red, red] + moving, w, h, chunk=1024)
    header, frames, _ = decode(data)
    if header != (w, h, 10, 0, 1024):
        raise TestFailure(f"header: {header}")
    if len(frames) != 22:
        raise TestFailure(f"{len(frames)} frames, not 22")
    if frames[0] != bytes([0xe0]) * (w * h) or frames[1] != frames[0]:
        raise TestFailure("red frames do not decode to red")
    if frames[2][0] != 0x03 or frames[2][15 * w + 5] != 0xfc:
        raise TestFailure(f"moving frame: {frames[2][0]:#x} {frames[2][15 * w + 5]:#x}")
    if len(data) <= 1024:
        raise TestFailure("the video should span several chunks")
    first = len(encode([red], w, h))
    if len(encode([red, red], w, h)) - first > 4 + w * h // 64 + 1:
        raise TestFailure("a frame like the one before should be all keep codes")
    grey = bytes((0x30, 0x30, 0x30)) * (w * h)
    _, [shade], _ = decode(encode([grey], w, h))
    if len(set(shade)) < 2:
        raise TestFailure("a shade between two colours should be dithered")
    sound = bytes(range(256)) * 10          # 2560 samples, frames want 3 x 1067
    header, frames, sounds = decode(encode([red] * 3, w, h, fps=15, sound=sound))
    if header[3] != 16000 or len(frames) != 3:
        raise TestFailure(f"with sound: header {header}, {len(frames)} frames")
    if [len(s) for s in sounds] != [1066, 1067, 1067] or b"".join(sounds)[:2560] != sound:
        raise TestFailure(f"sound split as {[len(s) for s in sounds]}")
    if set(b"".join(sounds)[2560:]) != {128}:
        raise TestFailure("missing sound should be silence")
    bad = subprocess.run([VIVENC, "0", "1", "1"], capture_output=True)
    if bad.returncode != 1 or b"usage" not in bad.stderr:
        raise TestFailure(f"bad size: {bad.returncode} {bad.stderr!r}")


def test_sample_video_decodes():
    header, frames, sounds = decode(open("samples/demo.viv", "rb").read())
    if header[:4] != (320, 180, 15, 16000) or len(frames) != 225:
        raise TestFailure(f"samples/demo.viv: header {header}, {len(frames)} frames")
    if sum(map(len, sounds)) != 15 * 16000:
        raise TestFailure(f"samples/demo.viv: {sum(map(len, sounds))} samples")
