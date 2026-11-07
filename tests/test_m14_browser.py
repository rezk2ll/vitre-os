import socket
import threading

from harness import SHELL_READY, Vm
from test_m11_net import run
from test_m13_tcp import serve_once
from test_mouse import move


def click(vm):
    for down in (True, False):
        vm.qmp("input-send-event",
               events=[{"type": "btn", "data": {"down": down, "button": "left"}}])


EXAMPLE = b"""<!doctype html>
<html>
<head>
    <title>Example Domain</title>
    <style type="text/css">
    body { background-color: #f0f0f2; margin: 0; }
    </style>
</head>
<body>
<div>
    <h1>Example Domain</h1>
    <p>This domain is for use in illustrative examples in documents. You may use this
    domain in literature without prior coordination or asking for permission.</p>
    <!-- a comment <p>hidden</p> -->
    <p>Fish &amp; chips &lt;3 &#65;</p>
    <p><a href="https://www.iana.org/domains/example">More information...</a></p>
    <ul><li>one</li><li><a href='/two'>two</a></li></ul>
</div>
</body>
</html>
"""


def page(html):
    return b"HTTP/1.0 200 OK\r\nContent-Type: text/html\r\n\r\n" + html


def test_view_wraps_words():
    words = b" ".join(b"word%02d" % i for i in range(30))
    port = serve_once(page(b"<p>" + words + b"</p>"))
    with Vm("m14_view", net=True) as vm:
        vm.wait_for(SHELL_READY)
        run(vm, f"view 10.0.2.2:{port}", r"word00 word01 .*word13\s+word14 .*word27\s+word28 word29\s")


def test_view_lays_out_example():
    port = serve_once(page(EXAMPLE))
    with Vm("m14_example", net=True) as vm:
        vm.wait_for(SHELL_READY)
        text = run(vm, f"view 10.0.2.2:{port}", r"\[view\] Example Domain[\s\S]*\[2\] /two\s").group(0)
    assert "Example Domain\r\n\r\nThis domain is for use in illustrative examples in documents. You may use this" in text \
        and "Fish & chips <3 A" in text and "More information...[1]" in text and "* one\r\n* two[2]" in text \
        and "[1] https://www.iana.org/domains/example" in text \
        and not any(s in text for s in ["hidden", "background-color", "<p>", "\n>"]), text


def test_browse_shows_and_scrolls():
    lines = b"".join(b"line %03d<br>" % i for i in range(200))
    port = serve_once(page(b"<title>Long page</title><h1>Top</h1>" + lines))
    with Vm("m14_browse", net=True) as vm:
        pos = vm.wait_for(SHELL_READY).end()
        vm.sendkeys(f"browse 10.0.2.2:{port}\n")
        vm.wait_screen(r"Long page[\s\S]*Top[\s\S]*line 000[\s\S]*10\.0\.2\.2")
        vm.press("end")
        vm.wait_screen(r"line 199")
        vm.press("home")
        vm.wait_screen(r"line 000")
        vm.sendkeys("q")
        vm.wait_for(r"\r\nvitre> ", start=pos)


def serve_pages(pages):
    sock = socket.create_server(("127.0.0.1", 0))

    def loop():
        while True:
            conn = sock.accept()[0]
            with conn:
                data = b""
                while b"\r\n\r\n" not in data:
                    chunk = conn.recv(4096)
                    if not chunk:
                        break
                    data += chunk
                path = data.split(b" ")[1].decode() if b" " in data else "/"
                body = pages.get(path, b"<title>Missing</title>")
                conn.sendall(body if body.startswith(b"HTTP/") else page(body))

    threading.Thread(target=loop, daemon=True).start()
    return sock.getsockname()[1]


def test_browse_follows_links():
    port = serve_pages({
        "/": b"<title>Home</title><a href='docs/a.html'>a</a>",
        "/docs/a.html": b"<title>Page A</title><a href=c.html>c</a> <a href='/b'>b</a>",
        "/docs/c.html": b"<title>Page C</title>", "/b": b"<title>Page B</title>",
    })
    with Vm("m14_links", net=True) as vm:
        vm.wait_for(SHELL_READY)
        vm.sendkeys("browse\n")
        vm.wait_screen(r"Vitre browser")
        vm.sendkeys(f"g10.0.2.2:{port}/\n")
        vm.wait_screen(r"^ Home")
        vm.sendkeys("1\n")
        vm.wait_screen(r"^ Page A[\s\S]*http://10\.0\.2\.2:\d+/docs/a\.html")
        vm.sendkeys("1\n")
        vm.wait_screen(r"^ Page C[\s\S]*/docs/c\.html")
        vm.sendkeys("b")
        vm.wait_screen(r"^ Page A")
        vm.sendkeys("2\n")
        vm.wait_screen(r"^ Page B[\s\S]*:\d+/b ")
        vm.sendkeys("bb")
        vm.wait_screen(r"^ Home")


def redirect(to, code=301):
    return f"HTTP/1.1 {code} Moved\r\nlocation:  {to}\r\n\r\n".encode()


def test_browse_follows_redirects():
    port = serve_pages({
        "/old": redirect("/docs/"), "/docs/": redirect("new.html", 302),
        "/docs/new.html": b"<title>Moved here</title>",
        "/loop": redirect("/loop"),
    })
    with Vm("m14_redirect", net=True) as vm:
        vm.wait_for(SHELL_READY)
        vm.sendkeys(f"browse 10.0.2.2:{port}/old\n")
        vm.wait_screen(r"^ Moved here[\s\S]*:\d+/docs/new\.html ")
        vm.sendkeys(f"g10.0.2.2:{port}/loop\n")
        vm.wait_screen(r"redirects too many times[\s\S]*:\d+/loop ")


def point(vm, col, row):
    """Moves the pointer onto a character cell of the screen."""
    move(vm, -5000, -5000)
    move(vm, col * 8 + 4, row * 16 + 8)


def test_click_follows_links():
    port = serve_pages({
        "/": b"<title>Home</title><p>Go to <a href=/b>the second page</a> now."
             b" <a href=/c>c</a>",
        "/b": b"<title>Page B</title>", "/c": b"<title>Page C</title>",
    })
    with Vm("m14_click", net=True) as vm:
        vm.wait_for(SHELL_READY)
        vm.sendkeys(f"browse 10.0.2.2:{port}/\n")
        vm.wait_screen(r"\n Go to the second page\[1\] now\. c\[2\]")
        point(vm, 14, 1)                # "second"
        click(vm)
        vm.wait_screen(r"^ Page B")
        vm.sendkeys("b")
        vm.wait_screen(r"^ Home")
        point(vm, 34, 1)                # the "[2]" after c
        click(vm)
        vm.wait_screen(r"^ Page C")
        vm.sendkeys("b")
        vm.wait_screen(r"^ Home")
        point(vm, 3, 1)                 # plain text: stays
        click(vm)
        vm.sendkeys("j")
        vm.wait_screen(r"^ Home")
