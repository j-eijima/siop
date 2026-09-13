# 0013 — The test RP reports its own http redirect_uri

## Context

OpenID Connect Core 3.2.2.1 forbids the http scheme for the redirection URI in the Implicit Flow,
unless the client is a native application, which may use it with `localhost` or the loopback
literals `127.0.0.1` and `[::1]`.

The test RP's default redirect URI is `http://localhost:8080/callback.html`. The RP is a web page,
not a native application, so that default is outside the exception — even though its traffic never
leaves the machine, which is the reason the exception exists. The spec draws the line by the kind of
client, not by the network path.

The request page already reports departures from the spec without blocking them.

## Decision

The RP applies the rule as written. An http redirect URI is reported unless the client is native
and the host is one of the three the spec names, spelled exactly as it names them. The RP never
counts itself as native, so its own default is reported like any other departure.

## Consequences

The request page shows a warning on its defaults, every time. That is the RP describing itself
accurately, not a fault to be cleared: the warning goes away only when the RP is hosted on https,
which is also the way to test within the spec
([0006](0006-rp-verifies-in-the-browser.md) covers what https takes on a device).

A native client, if one is ever added, gets the exception through the same function.
