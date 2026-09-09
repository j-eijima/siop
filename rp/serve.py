#!/usr/bin/env python3
"""Serves the test RP.

Binds all interfaces so a device on the same network can reach it, and honours
$PORT so it can be deployed as-is to a host that assigns one.

WebCrypto — and therefore the verification this RP exists to show — only runs
in a secure context. `http://localhost` counts as one; `http://192.168.x.x`
does not, so a device reaching this over the LAN gets a page that loads and
cannot verify anything.

--tls serves HTTPS with a self-signed certificate, which is enough for a
desktop browser where the warning can be clicked through. It is not enough for
iOS: Safari rejects a certificate it does not trust outright, offering nothing
to click, so a device needs the certificate installed and trusted or the RP
needs to be served from somewhere with a real one.
"""

import argparse
import http.server
import os
import ipaddress
import socket
import socketserver
import ssl
import subprocess
import sys
from functools import partial
from pathlib import Path

CERT_DIR = Path(__file__).parent / ".tls"

# A client that connects and then says nothing must not hold a worker forever.
HANDSHAKE_TIMEOUT_SECONDS = 10


class Server(socketserver.ThreadingTCPServer):
    """IPv4 only. See [DualStackServer] and [listen]."""

    allow_reuse_address = True
    daemon_threads = True
    tls_context = None

    def get_request(self):
        """Wraps each connection rather than the listening socket.

        The handshake is deliberately deferred: doing it here would run it in
        the accept loop, where one client that connects and never speaks would
        stop every other connection from being served.
        """
        connection, address = self.socket.accept()
        if self.tls_context is None:
            return connection, address
        wrapped = self.tls_context.wrap_socket(
            connection, server_side=True, do_handshake_on_connect=False
        )
        return wrapped, address

    def finish_request(self, request, client_address):
        """Runs in a worker thread, which is where the handshake belongs.

        A client that rejects the certificate fails here. Reporting it with the
        address it came from is what distinguishes a device that will not accept
        the certificate from one that never connected — otherwise both look like
        silence.
        """
        if self.tls_context is not None:
            request.settimeout(HANDSHAKE_TIMEOUT_SECONDS)
            try:
                request.do_handshake()
            except (ssl.SSLError, OSError) as error:
                print(f"{client_address[0]} - TLS handshake failed: {error}")
                return
            request.settimeout(None)
        super().finish_request(request, client_address)


class DualStackServer(Server):
    """Serves both stacks, so `localhost` works whichever one it resolves to."""

    address_family = socket.AF_INET6

    def server_bind(self):
        self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
        super().server_bind()


def listen(port, handler):
    """Prefers dual-stack, falls back to IPv4.

    Not every container runtime has IPv6 at all, and refusing to start there —
    when IPv4 would have served every request — would be a strange way for a
    static file server to fail.
    """
    try:
        return DualStackServer(("::", port), handler)
    except OSError:
        return Server(("0.0.0.0", port), handler)


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

    Shaped to Apple's requirements for TLS server certificates: a
    subjectAltName for the host, extendedKeyUsage of serverAuth, not a CA, and
    a lifetime under 825 days. A certificate that misses any of these is
    rejected outright — Safari offers no way past it, so it looks like the
    server is broken rather than untrusted.
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
            "-addext", "extendedKeyUsage=serverAuth",
            "-addext", "keyUsage=digitalSignature,keyEncipherment",
            "-addext", "basicConstraints=critical,CA:FALSE",
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

    # $PORT is how a container host tells a program where to listen.
    port = args.port or int(os.environ.get("PORT") or 0) or (8443 if args.tls else 8080)
    scheme = "https" if args.tls else "http"
    lan = args.host or lan_address()

    root = Path(__file__).parent / "public"
    handler = partial(Handler, directory=str(root))
    httpd = listen(port, handler)

    if args.tls:
        try:
            cert, key = certificate_for(lan)
        except (subprocess.CalledProcessError, FileNotFoundError) as error:
            print(f"could not generate a certificate: {error}", file=sys.stderr)
            return 1
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(cert, key)
        httpd.tls_context = context

    print(f"{scheme}://localhost:{port}/")
    print(f"{scheme}://{lan}:{port}/   (from another device on this network)")
    if args.tls:
        print("The certificate is self-signed, so the browser warns once. Accepting it")
        print("makes the origin a secure context, which is what WebCrypto needs.")
    with httpd:
        httpd.serve_forever()


if __name__ == "__main__":
    sys.exit(main() or 0)
