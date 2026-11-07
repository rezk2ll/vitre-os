import re
import socket
import threading

from harness import SHELL_READY, TestFailure, Vm
from test_desktop import open_icon, wait_desktop, wait_pixel
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
    return encode(frames, W, H, fps=10, chunk=1024)


def serve_ranges(files, seen):
    """HTTP/1.0 with Range: bytes=a-b, as a real web server answers it."""
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
                m = re.search(rb"\r\nRange: bytes=(\d+)-(\d+)", data)
                seen.append((path, m and (int(m.group(1)), int(m.group(2)))))
                body = files.get(path)
                if body is None:
                    conn.sendall(b"HTTP/1.0 404 Not Found\r\n\r\nmissing")
                elif not m:
                    conn.sendall(b"HTTP/1.0 200 OK\r\n\r\n" + body)
                elif int(m.group(1)) >= len(body):
                    conn.sendall(b"HTTP/1.0 416 Range Not Satisfiable\r\n\r\n")
                else:
                    a, b = int(m.group(1)), min(int(m.group(2)), len(body) - 1)
                    conn.sendall(b"HTTP/1.0 206 Partial Content\r\nContent-Range: bytes "
                                 + f"{a}-{b}/{len(body)}".encode() + b"\r\n\r\n" + body[a:b + 1])

    threading.Thread(target=loop, daemon=True).start()
    return sock.getsockname()[1]


def test_play_streams_a_video_in_chunks():
    video, seen = clip(), []
    port = serve_ranges({"/clip.viv": video}, seen)
    with Vm("play", net=True) as vm:
        pos = vm.wait_for(SHELL_READY).end()
        vm.sendkeys(f"play http://10.0.2.2:{port}/clip.viv\n")
        wait_pixel(vm, 512, 384, RED)
        wait_pixel(vm, 512, 384, GREEN)
        pos = vm.wait_for(r"\[play\] 40 frames\r\n", start=pos, timeout=30).end()
        chunks = [r for p, r in seen if p == "/clip.viv"]
        if chunks[:2] != [(0, 199999), (1024, 2047)] or len(chunks) < len(video) // 1024:
            raise TestFailure(f"ranges asked for: {chunks}")

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


def test_desktop_video_icon_plays_a_url():
    port = serve_ranges({"/clip.viv": clip()}, [])
    with Vm("desktop_video", net=True) as vm:
        pos = vm.wait_for(SHELL_READY).end()
        vm.sendkeys("desktop\n")
        wait_desktop(vm)
        open_icon(vm, "Video")
        vm.wait_screen(r"video URL")
        vm.sendkeys(f"http://10.0.2.2:{port}/clip.viv\n")
        wait_pixel(vm, 512, 384, RED)
        vm.wait_for(r"\[play\] 40 frames\r\n", start=pos, timeout=30)
        vm.wait_screen(r"press a key or click to go back")
        vm.sendkeys(" ")
        wait_desktop(vm)
