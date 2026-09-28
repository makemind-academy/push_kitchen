#!/usr/bin/env python3
"""push-kitchen: after subscribing, the screen makes no tool call; the server says the queue moved and the screen re-reads it."""
import os
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "tools"))
from appplayer import AppPlayer  # noqa: E402
from mcpclient import HttpServer, serve_http  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.join(HERE, "kitchen_server")
CAP = os.path.join(HERE, "captures")

PORT, URL = 8767, "http://localhost:8767/mcp"
with serve_http(["dart", "run", "bin/server.dart", f"--http={PORT}"], cwd=SERVER, port=PORT):
    side = HttpServer(URL)
    ap = AppPlayer()
    ap.register_http_server("com.makemind.sample.kitchen", "Kitchen pass", URL)
    ap.restart()
    ap.open_server("com.makemind.sample.kitchen")
    ap.wait_text("#71")                        # the first ticket arrived by notification
    ap.shot(f"{CAP}/01_first.png")
    ap.wait_text("3 open")
    ap.expect_aligned("#", min_rows=3, edge="left")
    ap.shot(f"{CAP}/02_three_waiting.png")
    st = side.call("kitchen.stats")
    assert st["opens"] >= 1 and st["dones"] == 0, st
    assert st["told"] >= 3, st
    assert st["told"] <= st["reads"] <= st["told"] + st["opens"] + 1, f"reads must follow notifications, not a poll: {st}"
    ap.tap("Bump")
    ap.wait_text("2 open")
    ap.shot(f"{CAP}/03_after_done.png")
    st2 = side.call("kitchen.stats")
    assert st2["dones"] == 1 and st2["told"] == st["told"] + 1, st2
print("push-kitchen: three tickets arrived by notification, no polling, one bumped from the screen")
