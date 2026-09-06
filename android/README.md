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
| Pairwise subjects (7.1 `subject_types_supported`) | `SiopKeyStore`, a key per `client_id` |

- Signing is RS256 with a 2048-bit RSA key, which the spec requires
- A separate key per RP, so the subject really is pairwise as the metadata says: two RPs cannot
  tell they are talking to the same person. `SiopKeyStore` resolves a key from the `client_id`;
  `EphemeralKeyStore` keeps them in memory for tests and tools, and the app backs it with the
  Android Keystore
- A key is created when the user answers an RP, never when a request merely arrives. `client_id`
  comes from whoever sent the request, so allocating on display would let unanswered requests
  fill the keystore and stall on RSA generation
- Devices that ran the earlier single-key version present new subjects: the old key was shared
  across RPs, and any scheme that preserved it would preserve the linkability that pairwise keys
  exist to remove. There is no migration

### Using it

```kotlin
val keys = AndroidKeystoreKeyStore("jp.example.siop.key")
val response = SelfIssuedOp(keys).handle(incomingOpenIdUrl)  // openid://?response_type=id_token&...
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

## app

A Compose app that receives the `openid:` authorization endpoint.

```
./gradlew :app:assembleDebug
./gradlew :app:connectedDebugAndroidTest   # needs a running emulator or device
```

### Screens and flow

1. **Identity** — the `sub` this device presents (a JWK thumbprint), its public key, and the
   Discovery metadata
2. **Consent** — shown on receiving `openid://...`. It presents the requester
   (`client_id` = `redirect_uri`), the requested scopes, and the `nonce` / `state`. A SIOP cannot
   authenticate the RP, so the requester's URL is labelled unverified rather than dressed up as a
   trusted identity
3. **Response** — approving issues an ID Token and opens
   `redirect_uri#id_token=...&state=...`. Refusing returns `#error=access_denied`, as
   Section 3.1.2.6 prescribes. Section 7.2 lets `client_id` name any URI, so the redirect can be
   one no installed app opens; that is reported rather than counted as delivered

The signing key lives in the Android Keystore (`SiopKeyStore`), so `sub` is the same on every
launch and the private key never leaves the keystore.

### Trying it

```
adb shell am start -a android.intent.action.VIEW \
  -d "'openid://?response_type=id_token&client_id=https%3A%2F%2Fclient.example.org%2Fcb\
&scope=openid%20profile&state=af0ifjsldkj&nonce=n-0S6_WzA2Mj'"
```

## Not done yet

- `request` / `request_uri` support (Request Object). Until then the metadata sets
  `request_parameter_supported` and `request_uri_parameter_supported` to false — the latter
  defaults to true when omitted, so silence would advertise it
- Returning standard claims according to the `claims` parameter
