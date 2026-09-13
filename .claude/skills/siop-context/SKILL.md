---
name: siop-context
description: Where to look before changing anything in the SIOP example implementation — what the project is, which documents are authoritative for requirements, behaviour, and design decisions, and the rules that changes have to hold to. Use at the start of any task in this repository, and whenever a task touches app or RP behaviour, documentation, or a new implementation.
---

# SIOP — orientation

An example implementation of Self-Issued OpenID Provider (OpenID Connect Core 1.0, Section 7).
The same protocol is implemented once per OS in that OS's default language, and every
implementation is checked against one shared Relying Party in `rp/`.

Read only what the task needs. The four kinds of document do not overlap on purpose.

| Question | Where it is answered |
|---|---|
| What is this, what is built, how do I run it | `README.md` at the repository root, then the `README.md` of the directory being changed |
| What is the app supposed to do, and what counts as acceptance | `docs/specs/` — its `README.md` says what belongs there and how it is written |
| Why was it done this way | `docs/decisions/`, indexed by the `siop-decisions` skill. Read the index, then only the records the task touches |
| How am I expected to work here | the local `CLAUDE.md`, if present |

## Rules that hold everywhere

- Documentation ships in English and Japanese as a `README.md` / `README.ja.md` pair. English is
  canonical: change it first, change the Japanese in the same commit, never one alone. Run
  `python3 tools/check-docs.py`.
- Verification is always handed to a *different* implementation than the one that issued the
  token. A token verified only by its own issuer proves nothing.
- Commit messages are English.
- Nothing under `.claude/` is documentation the project ships; it is configuration for whoever
  works here, and `tools/check-docs.py` leaves it alone.

## Where a new document goes

A statement about what the apps should do is behaviour with acceptance conditions, and goes to
`docs/specs/`. A statement about why a design goes one way is a numbered record in
`docs/decisions/`, added to the `siop-decisions` index in the same change. A README says what
exists, not what is promised. Neither of the first two is repeated in the other.
