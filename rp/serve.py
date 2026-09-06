#!/usr/bin/env python3
"""Serves the test RP over HTTP.

Binds all interfaces so a physical device on the same network can reach it.
WebCrypto needs a secure context, which localhost satisfies; for a device,
use http://<this machine's LAN address>:8080 (browsers treat plain HTTP on a
LAN address as insecure, so verification there requires a tunnel or HTTPS).
"""

import argparse
import http.server
import socket
from functools import partial
from pathlib import Path


class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, fmt, *args):
        print(f"{self.address_string()} - {fmt % args}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8080)
    args = parser.parse_args()

    root = Path(__file__).parent / "public"
    handler = partial(Handler, directory=str(root))
    with http.server.ThreadingHTTPServer(("0.0.0.0", args.port), handler) as httpd:
        lan = socket.gethostbyname(socket.gethostname())
        print(f"http://localhost:{args.port}/  (LAN: http://{lan}:{args.port}/)")
        httpd.serve_forever()


if __name__ == "__main__":
    main()
