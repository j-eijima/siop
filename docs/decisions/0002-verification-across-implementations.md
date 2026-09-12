# 0002 — A token is verified by an implementation other than its issuer

## Context

An implementation that issues a token and then verifies it with its own code agrees with itself
whatever it does. Every such test passes while the implementation is self-consistently wrong, and
the more implementations there are, the more places this can hide.

## Decision

Verification is always handed to a different implementation than the one that produced the token.
`rp/` is the shared Relying Party every implementation is checked against, and a new
implementation counts as minimally conformant once authentication succeeds there.

Two arrangements carry this: a real Swift-signed token committed as a fixture, verified by
JavaScript without a Swift toolchain, and the same checks run against whatever the current Swift
build produces, skipped where SIOPKit cannot be built. The first keeps the suite runnable
anywhere; the second stops a stale fixture from hiding a regression.

## Consequences

Tests in one language must not depend on another language's toolchain, so fixtures are committed
and the raw cross-checks are a separate suite that skips itself. When adding an implementation,
start by feeding `siop-issue` output to the new verifier.
