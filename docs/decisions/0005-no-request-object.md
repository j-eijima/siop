# 0005 — The metadata denies the Request Object explicitly

## Context

The static metadata was copied from Section 7.1's example configuration, including
`request_object_signing_alg_values_supported`. No implementation handles `request` or
`request_uri`, so an RP that believed the advertisement would send a request object and have it
silently ignored.

Dropping the entry is not enough on its own: under OpenID Connect Discovery Section 3,
`request_uri_parameter_supported` defaults to *true* when absent, so saying nothing advertises the
capability. An RP honouring that default would put the nonce inside a request object no parser
fetches, and then be rejected for a missing nonce.

## Decision

Both `request_parameter_supported` and `request_uri_parameter_supported` are present and false,
and `request_object_signing_alg_values_supported` is absent. A test in each implementation holds
the metadata to what is actually implemented rather than to what the spec's example lists.

## Consequences

Implementing the Request Object is still open. Whoever does it changes the flags in the same
change, and the metadata tests will insist on it.
