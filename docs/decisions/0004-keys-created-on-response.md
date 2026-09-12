# 0004 — A key is created when the user answers, not when a request arrives

## Context

With a key per `client_id` ([0003](0003-pairwise-keys-per-rp.md)), something has to decide when
that key comes into existence. Generating it as the consent screen appears is the obvious place,
and it is wrong: `client_id` comes from whoever sent the request, so any app or page could fill
the Keychain with keys by sending requests nobody answers, and each 2048-bit RSA generation stalls
the screen it is supposed to be drawing.

## Decision

The key is created when the user responds. The consent screen shows the established subject when
one exists, and says a new one will be made when it does not.

## Consequences

The consent screen cannot show the subject that would be created, only that one will be — so the
scenarios in [docs/specs/consent/](../specs/consent/) split on whether this Relying Party has been
answered before. Declining leaves no key behind, though it does return `access_denied`.
