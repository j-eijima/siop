---
name: siop-decisions
description: Design decisions already made in the SIOP reference implementation and the reasoning behind them, as an index of numbered records. Use before changing key handling, subject derivation, the advertised metadata, the RP's verification path, the cross-implementation test arrangement, the push review gate, or the documentation rules — and before proposing something that looks like an obvious improvement, in case it was already decided against.
---

# SIOP — decision records

Reasoning that does not survive in the code. These accumulate as a log, so **read the index below,
then open only the records the current task touches.** The records themselves live in
`docs/decisions/`, numbered in the order they were made; this file is their only index, and
`tools/check-docs.py` fails if a record is missing from it or a row points at nothing.

| # | Decision | Open it when |
|---|---|---|
| [0001](docs/decisions/0001-one-language-per-os.md) | Each OS is implemented in its default language, in a fixed order | Adding an implementation, or proposing a cross-platform framework |
| [0002](docs/decisions/0002-verification-across-implementations.md) | A token is always verified by an implementation other than the one that issued it | Adding or restructuring tests, or adding an implementation |
| [0003](docs/decisions/0003-pairwise-keys-per-rp.md) | One signing key per `client_id`, with no migration from the old shared key | Touching key storage, `sub`, or anything about linkability |
| [0004](docs/decisions/0004-keys-created-on-response.md) | A key is created when the user answers, never when a request arrives | Touching the consent screen or when keys are generated |
| [0005](docs/decisions/0005-no-request-object.md) | The metadata says the Request Object is unsupported, both flags explicitly false | Touching the static metadata, or adding `request` / `request_uri` |
| [0006](docs/decisions/0006-rp-verifies-in-the-browser.md) | The RP verifies in the browser; the ID Token never reaches its server | Changing the RP's verification path or adding a server endpoint |
| [0007](docs/decisions/0007-push-reviewed-by-the-other-agent.md) | A push is reviewed by the coding agent that did not write it | Touching `tools/hooks/`, the push gate, or CI |
| [0008](docs/decisions/0008-bilingual-docs-checked-mechanically.md) | Documentation is bilingual, and only its mechanical failures are enforced | Adding documentation, or changing `tools/check-docs.py` |
| [0009](docs/decisions/0009-specs-and-decisions-split.md) | Behaviour lives in `docs/specs/`, reasoning lives here | Deciding where a new document goes |
