from harness import SHELL_READY, Vm
from test_m11_net import run
from test_m13_tcp import serve_once


def page(html):
    return b"HTTP/1.0 200 OK\r\nContent-Type: text/html\r\n\r\n" + html


def test_view_wraps_words():
    words = b" ".join(b"word%02d" % i for i in range(30))
    port = serve_once(page(b"<p>" + words + b"</p>"))
    with Vm("m14_view", net=True) as vm:
        vm.wait_for(SHELL_READY)
        run(vm, f"view 10.0.2.2:{port}", r"word00 word01 .*word13\s+word14 .*word27\s+word28 word29\s")
