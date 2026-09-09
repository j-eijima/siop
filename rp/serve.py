#!/usr/bin/env python3
"""Serves the test RP.

Binds all interfaces so a device on the same network can reach it.

WebCrypto — and therefore the verification this RP exists to show — only runs
in a secure context. `http://localhost` counts as one; `http://192.168.x.x`
does not, so a phone or tablet reaching the Mac over the LAN gets a page that
cannot verify anything. Passing --tls serves HTTPS with a self-signed
certificate instead: the browser will warn once, and accepting the warning
makes the origin a secure context, with nothing installed on the device.
"""

import argparse
import http.server
import ipaddress
import socket
import socketserver
import ssl
import subprocess
import sys
from functools import partial
from pathlib import Path

CERT_DIR = Path(__file__).parent / ".tls"


class Server(socketserver.ThreadingTCPServer):
    """Listens on both stacks, so `localhost` works whichever one it resolves to."""

    address_family = socket.AF_INET6
    allow_reuse_address = True
    daemon_threads = True

    def server_bind(self):
        self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
        super().server_bind()


class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, fmt, *args):
        print(f"{self.address_string()} - {fmt % args}")


def lan_address():
    """The address a device on the same network would use to reach this Mac."""
    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        # Nothing is sent; this just asks the routing table which interface wins.
        probe.connect(("192.0.2.1", 1))
        return probe.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        probe.close()


def certificate_for(host):
    """A self-signed certificate naming `host`, generated once and reused.

    Regenerated when the address changes, since a certificate that does not
    name the host the browser asked for is rejected outright rather than
    warned about.
    """
    CERT_DIR.mkdir(exist_ok=True)
    cert, key = CERT_DIR / f"{host}.crt", CERT_DIR / f"{host}.key"
    if cert.exists() and key.exists():
        return cert, key

    subject_alt = f"IP:{host}" if is_ip(host) else f"DNS:{host}"
    subprocess.run(
        [
            "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
            "-keyout", str(key), "-out", str(cert), "-days", "365",
            "-subj", f"/CN={host}",
            "-addext", f"subjectAltName={subject_alt},DNS:localhost,IP:127.0.0.1",
        ],
        check=True,
        capture_output=True,
    )
    print(f"self-signed certificate for {host} written to {CERT_DIR}")
    return cert, key


def is_ip(host):
    try:
        ipaddress.ip_address(host)
        return True
    except ValueError:
        return False


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int)
    parser.add_argument("--tls", action="store_true",
                        help="serve HTTPS, so a device on the LAN gets a secure context")
    parser.add_argument("--host", help="the name to put in the certificate (default: this Mac's LAN address)")
    args = parser.parse_args()

    port = args.port or (8443 if args.tls else 8080)
    scheme = "https" if args.tls else "http"
    lan = args.host or lan_address()

    root = Path(__file__).parent / "public"
    handler = partial(Handler, directory=str(root))
    httpd = Server(("::", port), handler)

    if args.tls:
        try:
            cert, key = certificate_for(lan)
        except (subprocess.CalledProcessError, FileNotFoundError) as error:
            print(f"could not generate a certificate: {error}", file=sys.stderr)
            return 1
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(cert, key)
        httpd.socket = context.wrap_socket(httpd.socket, server_side=True)

    print(f"{scheme}://localhost:{port}/")
    print(f"{scheme}://{lan}:{port}/   (from another device on this network)")
    if args.tls:
        print("The certificate is self-signed, so the browser warns once. Accepting it")
        print("makes the origin a secure context, which is what WebCrypto needs.")
    with httpd:
        httpd.serve_forever()


if __name__ == "__main__":
    sys.exit(main() or 0)
