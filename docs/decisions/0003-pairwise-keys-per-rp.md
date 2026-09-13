# 0003 — One signing key per Relying Party, with no migration

Superseded by [0011](0011-identities-per-rp.md).

## Context

The static metadata advertises pairwise subjects. An earlier version held a single key for the
device, so every RP saw the same `sub` and any two RPs could tell they were talking to the same
person — the metadata said one thing and the implementation did another.

## Decision

A separate key per `client_id`. The Keychain tag (and the Android equivalent) derives from the
`client_id`, so one RP sees the same subject on every visit and two RPs cannot correlate.

Devices carrying a key from the single-key version present new subjects. There is no migration:
any scheme that preserved the old key would preserve exactly the linkability the change exists to
remove.

## Consequences

RPs that key accounts on `sub` see a returning user as new after the upgrade. Accepted — this is a
reference implementation, and preserving the old subject would misrepresent what pairwise means.
Identity management ([docs/specs/identity/](../specs/identity/)) extends this
behaviour rather than replacing it.
