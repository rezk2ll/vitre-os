from harness import SHELL_READY, Vm
from test_m11_net import run
from test_m13_tcp import serve_once


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
