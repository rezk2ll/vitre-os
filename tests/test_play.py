import socket
import threading

from harness import SHELL_READY, TestFailure, Vm
from test_desktop import wait_pixel
from test_vivenc import encode

W, H = 64, 48
RED, GREEN = (255, 0, 0), (0, 255, 0)


def clip():
    """40 frames at 10 a second: red, then green, a white bar sliding along
    the top so every frame differs."""
    frames = []
    for k in range(40):
        rgb = bytearray(bytes(RED if k < 20 else GREEN) * (W * H))
        for y in range(4):
            for x in range(k, k + 8):
                rgb[(y * W + x) * 3:(y * W + x) * 3 + 3] = b"\xff\xff\xff"
        frames.append(bytes(rgb))
    return encode(frames, W, H, fps=10)


def serve(files, seen):
    sock = socket.create_server(("127.0.0.1", 0))

    def loop():
        while True:
            conn = sock.accept()[0]
            with conn:
                data = b""
                while b"\r\n\r\n" not in data:
                    part = conn.recv(4096)
                    if not part:
                        break
                    data += part
                path = data.split(b" ")[1].decode()
                seen.append(path)
                body = files.get(path)
                if body is None:
                    conn.sendall(b"HTTP/1.0 404 Not Found\r\n\r\nmissing")
                else:
                    conn.sendall(b"HTTP/1.0 200 OK\r\n\r\n" + body)

    threading.Thread(target=loop, daemon=True).start()
    return sock.getsockname()[1]


def test_play_shows_a_video():
    video, seen = clip(), []
    port = serve({"/clip.viv": video}, seen)
    with Vm("play", net=True) as vm:
        pos = vm.wait_for(SHELL_READY).end()
        vm.sendkeys(f"play http://10.0.2.2:{port}/clip.viv\n")
        wait_pixel(vm, 512, 384, RED)
        wait_pixel(vm, 512, 384, GREEN)
        pos = vm.wait_for(r"\[play\] 40 frames\r\n", start=pos, timeout=30).end()

        vm.sendkeys(f"play http://10.0.2.2:{port}/clip.viv\n")
        wait_pixel(vm, 512, 384, RED)
        vm.sendkeys("q")
        m = vm.wait_for(r"\[play\] (\d+) frames\r\n", start=pos)
        if not 0 < int(m.group(1)) < 40:
            raise TestFailure(f"q stopped after {m.group(1)} frames")
        pos = m.end()

        vm.sendkeys(f"play http://10.0.2.2:{port}/nope.viv\n")
        pos = vm.wait_for(r"\[play\] no Vitre video there\r\n", start=pos).end()
        vm.sendkeys("play\n")
        vm.wait_for(r"usage: play http://host/video\.viv", start=pos)
