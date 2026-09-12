# 0006 — The RP verifies in the browser, and the token never reaches its server

## Context

The test RP exists so that a person can watch Section 7.5 being applied. It also has to be
something anyone can run with no dependencies to install.

## Decision

Verification runs entirely in the browser on WebCrypto. The Implicit Flow returns the response in
the URL fragment, and browsers do not send fragments to the server, so the ID Token never reaches
one. `rp/serve.py` serves static files and nothing else.

## Consequences

WebCrypto needs a secure context. `http://localhost` qualifies; a LAN address over plain HTTP does
not, so a device reaching the RP that way gets a page that loads and can verify nothing. `--tls`
generates a self-signed certificate, which a desktop browser will let you click through and iOS
will not — Safari refuses an untrusted certificate outright, so a real iPhone needs the
certificate installed and trusted. Adding a server-side verification endpoint would undo the
property this decision exists for.
