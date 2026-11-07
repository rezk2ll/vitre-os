import struct
import subprocess

from harness import TestFailure

VIVENC = "build/vivenc"


def encode(frames, w, h, fps=10, chunk=None):
    args = [VIVENC, str(w), str(h), str(fps)] + ([str(chunk)] if chunk else [])
    return subprocess.run(args, input=b"".join(frames), capture_output=True, check=True).stdout


def decode(data):
    """The frames of a .viv file, each a bytes of one byte per pixel."""
    if data[:4] != b"VIV1":
        raise TestFailure(f"magic: {data[:4]!r}")
    w, h, fps, _, chunk = struct.unpack_from("<HHHHI", data, 4)
    frame, frames = bytearray(w * h), []
    for start in range(0, len(data), chunk):
        pos, end = start + (16 if start == 0 else 0), min(start + chunk, len(data))
        while pos + 4 <= end:
            (n,) = struct.unpack_from("<I", data, pos)
            if n == 0:
                break
            codes, pos, px = data[pos + 4:pos + 4 + n], pos + 4 + n, 0
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
    return (w, h, fps, chunk), frames


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
    (dw, dh, fps, chunk), frames = decode(data)
    if (dw, dh, fps, chunk) != (w, h, 10, 1024):
        raise TestFailure(f"header: {(dw, dh, fps, chunk)}")
    if len(frames) != 22:
        raise TestFailure(f"{len(frames)} frames, not 22")
    if frames[0] != bytes([0xe0]) * (w * h) or frames[1] != frames[0]:
        raise TestFailure("red frames do not decode to red")
    if frames[2][0] != 0x03 or frames[2][15 * w + 5] != 0xfc:
        raise TestFailure(f"moving frame: {frames[2][0]:#x} {frames[2][15 * w + 5]:#x}")
    if len(data) <= 1024:
        raise TestFailure("the video should span several chunks")
    if len(encode([red, red], w, h)) - 16 > 2 * (4 + 2 * (w * h // 64 + 1)):
        raise TestFailure("a still frame should cost a few bytes")
    bad = subprocess.run([VIVENC, "0", "1", "1"], capture_output=True)
    if bad.returncode != 1 or b"usage" not in bad.stderr:
        raise TestFailure(f"bad size: {bad.returncode} {bad.stderr!r}")
