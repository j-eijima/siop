# SIOP — Android

**English** | [日本語](README.ja.md)

Kotlin implementation of the Self-Issued OpenID Provider defined in Section 7 of
OpenID Connect Core 1.0.

## siopkit

The core logic. It is a plain JVM module: signing uses `java.security`, so the whole thing
builds and its tests run without the Android SDK.

```
./gradlew :siopkit:test
```

### What implements what

| Section | Implementation |
|---|---|
| 7.1 Discovery (static metadata) | `SelfIssuedMetadata` |
| 7.2 Registration (client_id = redirect_uri) | validation in `AuthorizationRequest` |
| 7.3 Parsing and validating the request | `AuthorizationRequest.parse` |
| 7.4 Issuing the Self-Issued ID Token | `SelfIssuedOp.respond` / `SelfIssuedIdToken` |
| 7.5 RP-side ID Token validation | `SelfIssuedIdTokenValidator` |
| RFC 7638 JWK thumbprint (the `sub` value) | `RsaPublicJwk.thumbprint()` |
| Pairwise subjects (7.1 `subject_types_supported`) | `SiopIdentityStore`: each identity is a key for one RP |

- Signing is RS256 with a 2048-bit RSA key, which the spec requires
- An identity is a key plus the names the user gives it, bound to one `client_id` for its whole
  life ([decision 0011](../docs/decisions/0011-identities-per-rp.md)). An RP may have several, but
  no identity answers a second RP, so the subject stays pairwise: two RPs cannot tell they are
  talking to the same person. `SiopIdentityStore` keeps the records and the keys behind them;
  `SiopIdentityStore.ephemeral()` keeps both in memory for tests
- A key is created when the user answers an RP or creates an identity, never when a request merely
  arrives. `client_id` comes from whoever sent the request, so allocating on display would let
  unanswered requests fill the keystore and stall on RSA generation
- A record that cannot be read stops everything rather than being skipped: dropping it would make
  its RP look new, and answering that RP would make a different subject
- Keys the key-per-RP version made (`SiopKeyStore`, one per `client_id`) are taken over as
  identities the first time their RP asks again, so the subject that RP already knows is kept.
  `SiopKeyStore` and `EphemeralKeyStore` remain for `siop-issue`, where nobody chooses anything
- Devices that ran the earlier single-key version present new subjects: the old key was shared
  across RPs, and any scheme that preserved it would preserve the linkability that pairwise keys
  exist to remove. There is no migration

### Using it

```kotlin
val store = SiopIdentityStore.ephemeral()
val request = AuthorizationRequest.parse(incomingOpenIdUrl)  // openid://?response_type=id_token&...
val identity = store.identitiesFor(request.clientId).firstOrNull()
    ?: store.createIdentity(request.clientId)                // only once the user has agreed
val response = SelfIssuedOp.respond(request, store.keyProvider(identity))
// Open response.redirectUrl to hand the id_token back to the RP in the fragment
```

## siop-issue

Prints a token for a request, in the same shape as the Swift `siop-issue`, so either
implementation's output can be fed to the other's verifier.

```
./gradlew :siop-issue:run --args="openid://?response_type=id_token&client_id=...&scope=openid&nonce=n1"
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

A Compose app that receives the `openid:` authorization endpoint, laid out as the
[UI mock](../rp/public/mock.html). It speaks English and Japanese, following the device
([decision 0012](../docs/decisions/0012-english-and-japanese-ui.md)).

```
./gradlew :app:assembleDebug
./gradlew :app:testDebugUnitTest          # the session, on the JVM
./gradlew :app:connectedDebugAndroidTest   # needs a running emulator or device
```

### Screens and flow

1. **Home** — every identity on the device, grouped by the RP it answers, and the Discovery
   metadata. Opening an identity shows its `sub`, its public key and the JSON its thumbprint is
   taken over, and lets it be renamed or deleted
2. **Consent** — shown on receiving `openid://...`. It shows the request as it arrived, lets the
   user choose or create the identity to answer as, and previews every value that will be signed,
   public key included, each marked with where it comes from: blue from the request, green from
   the chosen key, grey fixed or decided at signing. A SIOP cannot authenticate the RP, so the
   requester's URL is labelled unverified rather than dressed up as a trusted identity
3. **Response** — approving issues an ID Token and opens `redirect_uri#id_token=...&state=...`.
   Declining returns `#error=access_denied`, as Section 3.1.2.6 prescribes. Section 7.2 lets
   `client_id` name any URI, so the redirect can be one no installed app opens; that is reported
   rather than counted as delivered

Keys live in the Android Keystore (`AndroidKeystoreIdentityKeys`), so a `sub` is the same on every
launch and the private key never leaves the keystore. The records beside them — names, RP, when
each last answered — are JSON files where nothing is backed up (`FileIdentityRecords`): a key
cannot leave the keystore, so a record restored alone would list an identity that can never
answer. Both go when the app is removed. A record is synced to storage before a response signed by
its identity leaves the app, so the subject an RP learns is never one the device forgets.

A request waiting for the user is kept in the activity's saved state until it is answered, so it
comes back if Android ends the app's process meanwhile; one already answered does not.

If the identities cannot be read, a request stops with a message instead of reaching the consent
screen, and an RP whose identity exists but cannot sign is not answered as a new one unless the
user creates it.

### Trying it

```
adb shell am start -a android.intent.action.VIEW \
  -d "'openid://?response_type=id_token&client_id=https%3A%2F%2Fclient.example.org%2Fcb\
&scope=openid%20profile&state=af0ifjsldkj&nonce=n-0S6_WzA2Mj'"
```

### Tests

- `AuthenticationSessionTest` (`src/test/`) — what the session decides, on the JVM: no key before
  an answer, signing as the chosen identity, never answering another RP, failing closed when the
  identities cannot be read
- `AuthenticationFlowTest` — the screens, shown in English whatever the device's language
- `AndroidIdentityStorageTest` — the Keystore and the record files, including a token signed inside
  the keystore passing the verifier, and a key-per-RP key being taken over
- `EndToEndRpTest` — the full round trip through Chrome and the test RP. It needs the RP on the
  host, forwarded to the device, and skips itself otherwise:

  ```
  python3 rp/serve.py
  adb reverse tcp:8080 tcp:8080
  ```

## Not done yet

- `request` / `request_uri` support (Request Object). Until then the metadata sets
  `request_parameter_supported` and `request_uri_parameter_supported` to false — the latter
  defaults to true when omitted, so silence would advertise it
- Returning standard claims according to the `claims` parameter
