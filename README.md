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
`CLAUDE.md` is ignored, the way `.gitignore` and `project.yml` are not translated either.
