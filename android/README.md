# SIOP — Android

**English** | [日本語](README.ja.md)

Kotlin implementation of the Self-Issued OpenID Provider defined in Section 7 of
OpenID Connect Core 1.0.

## siopkit

The core logic. It is a plain JVM module: signing uses `java.security`, so the whole thing
builds and its tests run without the Android SDK.

```
gradle :siopkit:test
```

### What implements what

| Section | Implementation |
|---|---|
| 7.1 Discovery (static metadata) | `SelfIssuedMetadata` |
| 7.2 Registration (client_id = redirect_uri) | validation in `AuthorizationRequest` |
| 7.3 Parsing and validating the request | `AuthorizationRequest.parse` |
| 7.4 Issuing the Self-Issued ID Token | `SelfIssuedOp.handle` / `SelfIssuedIdToken` |
| 7.5 RP-side ID Token validation | `SelfIssuedIdTokenValidator` |
| RFC 7638 JWK thumbprint (the `sub` value) | `RsaPublicJwk.thumbprint()` |

- Signing is RS256 with a 2048-bit RSA key, which the spec requires
- `KeyPairProvider` takes any JCA key pair. Give it one from the Android Keystore so that `sub`
  stays stable across launches; `KeyPairProvider.generate()` produces an ephemeral one for tests

### Using it

```kotlin
val key = KeyPairProvider(keyPairFromAndroidKeystore)
val response = SelfIssuedOp(key).handle(incomingOpenIdUrl)  // openid://?response_type=id_token&...
// Open response.redirectUrl to hand the id_token back to the RP in the fragment
```

## siop-issue

Prints a token for a request, in the same shape as the Swift `siop-issue`, so either
implementation's output can be fed to the other's verifier.

```
gradle :siop-issue:run --args="openid://?response_type=id_token&client_id=...&scope=openid&nonce=n1"
```

## How this is checked against the other implementations

An implementation that issues and verifies only its own tokens can be self-consistently wrong, so
both directions are covered:

- `CrossImplementationTest` verifies a Swift-signed token with this Kotlin verifier. The token is
  the committed fixture in `rp/test/fixtures/`, so no Swift toolchain is needed here
- `rp/test/verify.test.mjs` verifies a Kotlin-signed token with the RP's JavaScript
  implementation

Refresh both fixtures with `rp/test/fixtures/regenerate.sh`, which needs Swift and a JDK.

## Not done yet

- The sample app: receiving `openid://`, the consent screen, and returning the response. That
  needs the Android SDK
- Keys held in the Android Keystore
- `request` / `request_uri` support (Request Object)
