# SIOP

**English** | [日本語](README.ja.md)

A reference implementation of
[Section 7, Self-Issued OpenID Provider](https://openid.net/specs/openid-connect-core-1_0.html#SelfIssued)
of OpenID Connect Core 1.0.

A Self-Issued OpenID Provider (SIOP) does away with the authorization server: the end user's own
device acts as the OpenID Provider. It signs an ID Token with a key it holds and carries the
matching public key inside the token as `sub_jwk`. The subject identifier `sub` is the JWK
thumbprint (RFC 7638) of that public key, so the user proves possession of a key to a Relying
Party without anyone having registered or issued an identifier for them.

Each OS is implemented in its own default language, and every implementation is checked against
one shared Relying Party.

## What this produces

- An SDK for using SIOP, with documentation
- A sample app that actually works

## What it is supposed to do

Behaviour the apps promise, and what counts as acceptance, lives in [docs/specs/](docs/specs/)
rather than here: identity management and selection, what the user must see before anything is
signed, and making every protocol parameter and its origin legible on both sides. Most of it is
requirement rather than built behaviour, and each specification says where it stands.

The reasoning behind decisions already made — pairwise keys, the denied Request Object, the
browser-only verification — is kept as numbered records in [docs/decisions/](docs/decisions/),
indexed by a coding-agent skill so that a task loads only the records it touches.

An interactive [HTML UI mock](rp/public/mock.html) demonstrates identity management, identity
selection, the response preview, and the RP's side-by-side parameter checks. Open the file in a
browser, or visit `/mock.html` on the test RP. It uses temporary in-memory keys and real WebCrypto
operations, without contacting an external RP. Reloading clears the identities. This is a UI
demonstration, not an implementation of these features in the native apps or an interoperability test.

## Status

Implementations are taken in the order below. Each OS uses its default language first;
cross-platform languages are optional additions.

| Order | | Language | State |
|---|---|---|---|
| 1 | [ios/](ios/) | Swift | ✅ SIOPKit (core) + SIOPApp (receives `openid:`) |
| 2 | [android/](android/) | Kotlin | ✅ siopkit (core) + app (receives `openid:`) |
| 3 | `cross_platform/flutter/` | Dart | Not started |
| 4 | `windows/` | C# | Not started |
| 5 | `macos/` | Swift | Not started |
| 6 | `cross_platform/rust/` | Rust | Not started |
| 7 | `linux/` | — | Not started |
| — | [rp/](rp/) | JavaScript | ✅ Test Relying Party shared by every implementation |

## What the spec asks for

| Section | Requirement |
|---|---|
| 7.1 Discovery | Static metadata; `authorization_endpoint` is `openid:` and the signing algorithm is RS256 |
| 7.2 Registration | There is no registration step, so the RP uses its redirect URI as the `client_id` |
| 7.3 Request | The authentication request arrives on `openid://` |
| 7.4 Response | `iss` is `https://self-issued.me` and `sub` is the thumbprint of `sub_jwk` |
| 7.5 Validation | The RP checks iss, sub, sub_jwk, the signature, aud and nonce |

## Running it

```
# Start the test RP (http://localhost:8080/)
python3 rp/serve.py

# iOS: SIOPKit unit tests
cd ios/SIOPKit && swift test

# iOS: the app and its end-to-end test (needs the RP running)
cd ios/SIOPApp && xcodegen generate
xcodebuild -project SIOPApp.xcodeproj -scheme SIOPApp \
  -destination 'platform=iOS Simulator,name=iPhone 17' test

# The RP's verification logic (Node only)
cd rp && node --test
```

Pick a simulator that your Xcode actually has; `iPhone 17` is only an example.

## How agreement between implementations is established

The more implementations there are, the easier it is for each to stay self-consistently wrong.
To prevent that, verification is always handed to a *different* implementation than the one that
produced the token.

- `rp/test/verify.test.mjs` — JavaScript verifies a real ID Token signed by Swift (SIOPKit). The
  token is committed as a fixture, so the suite runs without a Swift toolchain
- `rp/test/cross-implementation.test.mjs` — the same checks against whatever the *current* Swift
  build produces, so a stale fixture cannot hide an interoperability regression. Skipped
  automatically where SIOPKit cannot be built
- `ios/SIOPApp/UITests/EndToEndRPTests.swift` — drives the RP in Safari, hands the request to the
  app, and follows the issued token through to the RP verifying it
- `ios/SIOPKit`'s `siop-issue` CLI prints a token for any request. When adding an implementation
  in another language, feeding this output to your own verifier is the place to start

A new implementation counts as minimally conformant once authentication succeeds against the RP
in `rp/`.

## Before pushing

```
tools/install-hooks.sh
```

Installs a pre-push hook with the following policy:

| Push origin | Review |
|---|---|
| Claude Code | Codex adversarial review; approval required |
| Codex | No review (neither ordinary nor adversarial) |

The hook detects Codex through `CODEX_THREAD_ID` or `CODEX_SESSION_ID`, and Claude Code through
[`CLAUDECODE=1`](https://code.claude.com/docs/en/env-vars). An explicit `PUSH_AGENT` takes
precedence. From a plain terminal, or when nested agents leave both sets of markers, specify
which policy to apply:

```sh
PUSH_AGENT=codex git push   # No review
PUSH_AGENT=claude git push # Codex reviews
```

Unknown or ambiguous origins are refused. These markers select a policy, not establish
commit authorship. Codex-originated pushes log the skip and do not require a companion plugin.
Deletions and unchanged refs need no review or origin detection.

For Claude-originated pushes, only a successful Codex review with a structured `approve`
verdict allows the push. Failed runs, unparseable results, and a missing reviewer block it.
The reviewer compares a base against the checked-out HEAD, so this review path accepts only
fast-forward changes at HEAD, and new branches with a baseline advertised by the destination.
`tools/test-pre-push.sh` checks the routing, skips, and review gate against a scratch repository
with the reviewer stubbed.

The hook drives the local Codex CLI under your own credentials, so the review cannot run in CI
and only guards machines where the hook is installed. Hooks are not cloned; run the installer
once per clone. Override a single push deliberately with `git push --no-verify`.

Nothing in the gate is specific to this project. To use it elsewhere, copy `tools/hooks/`,
`tools/install-hooks.sh` and `tools/test-pre-push.sh`; the scripts require git, node and sh.
The Claude-originated review path also needs the authenticated Codex CLI and its companion
plugin. Companion lookup uses `CODEX_COMPANION` first, then `codex.companion` in Git config,
otherwise the newest installed version under
`~/.claude/plugins/cache/openai-codex/codex/*/scripts/codex-companion.mjs`.

## Documentation

English and Japanese are both supported. Every directory that documents itself carries
`README.md` and `README.ja.md`, and each links to the other. English is the canonical version:
change it first, and change the Japanese in the same commit — never one alone.

```
python3 tools/check-docs.py
```

Whether a translation says the same thing is a human judgement, but the ways a pair falls apart
are mechanical, so they are checked and enforced in CI: a missing counterpart, a section added on
one side only, a missing language switcher, a dead relative link.

Configuration for a coding agent is not documentation and is not part of this — a local
`CLAUDE.md` is ignored and `.claude/` is skipped, the way `.gitignore` and `project.yml` are not
translated either. The specifications under `docs/specs/` are documentation, and are checked like
the rest.
