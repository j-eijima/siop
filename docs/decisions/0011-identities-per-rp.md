# 0011 — An identity is a key for one RP, and an RP may have several

## Context

[0003](0003-pairwise-keys-per-rp.md) gave every RP one key, tagged by a hash of its `client_id`,
and never let the user see or choose it. The specifications in
[identity/](../specs/identity/) and [consent/](../specs/consent/) ask for identities the user can
create, name, choose between and delete, and the UI mock binds each identity to the RP it was made
for. A key per RP cannot express "answer this RP as someone else", and a tag derived from the
`client_id` has room for only one key per RP.

## Decision

An identity is a key plus names the user gives it, bound to one `client_id` for its whole life. An
RP may have several identities. No identity ever answers a second RP — the app refuses to sign
with one for any RP but its own — so the subject stays pairwise, which is what 0003 existed to
guarantee.

Keys get tags of their own instead of tags derived from the `client_id`. Each identity's record —
names, RP, when it last answered — is a Keychain item beside its key, so the two survive a reinstall
and are deleted together.

Keys made under 0003 are taken over as identities the first time their RP asks again, so the subject
that RP already knows is kept. A tag cannot be turned back into a `client_id`, so until then they
are not listed.

Keys are still created only by the user's hand: creating an identity, or answering an RP that has
none ([0004](0004-keys-created-on-response.md)). A request arriving creates nothing.

## Consequences

Both apps do this. Android followed 0003 until it was rebuilt on the UI mock, and takes over the keys
0003 made in the same way.

An RP can now be answered as more than one person, by the user's choice — which is also the only
way it can see two subjects from one device.

The home screen cannot list a key-per-RP key until its RP asks again, and says nothing about it
until then.

`SIOPKeyStore` stays in SIOPKit, and `SiopKeyStore` in siopkit, for tools such as `siop-issue`, where
nobody chooses anything.

Corrected: 2026-09-13 — Android now does this too; the consequences said only iOS did.
