# SIOP — iOS

**English** | [日本語](README.ja.md)

Swift implementation of the Self-Issued OpenID Provider defined in Section 7 of
OpenID Connect Core 1.0.

## SIOPKit

The core logic, as a Swift Package. No external dependencies — only Security and CryptoKit.

```
cd SIOPKit
swift build   # build
swift test    # unit tests (runnable on macOS)
```

### What implements what

| Section | Implementation |
|---|---|
| 7.1 Discovery (static metadata) | `SelfIssuedMetadata` |
| 7.2 Registration (client_id = redirect_uri) | validation in `AuthorizationRequest` |
| 7.3 Parsing and validating the request | `AuthorizationRequest(url:)` |
| 7.4 Issuing the Self-Issued ID Token | `SelfIssuedOP.handle(url:)` / `SelfIssuedIDToken` |
| 7.5 RP-side ID Token validation | `SelfIssuedIDTokenValidator` |
| RFC 7638 JWK thumbprint (the `sub` value) | `RSAPublicJWK.thumbprint()` |
| Pairwise subjects (7.1 `subject_types_supported`) | `SIOPKeyStore`, a key per `client_id` |

- Signing is RS256 with a 2048-bit RSA key, which the spec requires
- A separate key per RP, so the subject really is pairwise as the metadata says: two RPs cannot
  tell they are talking to the same person. `KeychainKeyStore` derives a Keychain tag from the
  `client_id`, so the same RP sees the same subject on every visit; `EphemeralKeyStore` keeps
  keys in memory for tests and tools
- A key is created when the user answers an RP, never when a request merely arrives. `client_id`
  comes from whoever sent the request, so allocating on display would let unanswered requests
  fill the Keychain and stall on RSA generation. The consent screen shows the established
  subject when there is one, and says a new one will be made when there is not
- Devices that ran the earlier single-key version present new subjects: the old key was shared
  across RPs, and any scheme that preserved it would preserve the linkability that pairwise keys
  exist to remove. There is no migration, and RPs that key accounts on `sub` will see a new user

### Using it

```swift
let keys = KeychainKeyStore(tagPrefix: "jp.example.siop.key")
let op = SelfIssuedOP(keyStore: keys)
let response = try op.handle(url: incomingOpenIDURL)  // openid://?response_type=id_token&...
// Open response.redirectURL to hand the id_token back to the RP in the fragment
```

## SIOPApp

A SwiftUI app that receives the `openid:` authorization endpoint. The Xcode project is generated
from `project.yml` by XcodeGen, so `.xcodeproj` is not in version control.

```
cd SIOPApp
xcodegen generate
xcodebuild -project SIOPApp.xcodeproj -scheme SIOPApp \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

### Screens and flow

1. **Identity** — the `sub` this device presents (a JWK thumbprint), its public key, and the
   Discovery metadata
2. **Consent** — shown on receiving `openid://...`. It presents the requester
   (`client_id` = `redirect_uri`), the requested scopes, and the `nonce` / `state`. A SIOP cannot
   authenticate the RP, so the requester's URL is labelled as unverified rather than dressed up
   as a trusted identity
3. **Response** — approving issues an ID Token and opens
   `redirect_uri#id_token=...&state=...`. Refusing returns `#error=access_denied`,
   as Section 3.1.2.6 prescribes. Section 7.2 lets `client_id` name any URI, so the redirect can
   be one nothing on the device opens; that is reported rather than counted as delivered

### Trying it against the RP

Start the test RP in `rp/` to exercise everything from sending a request through to verifying the
ID Token.

```
python3 ../rp/serve.py     # in another terminal
```

### Trying it on its own

```
xcrun simctl openurl booted "openid://?response_type=id_token\
&client_id=https%3A%2F%2Fclient.example.org%2Fcb&scope=openid%20profile\
&state=af0ifjsldkj&nonce=n-0S6_WzA2Mj"
```

### How the tests divide the work

- `AuthenticationFlowUITests` — covers the consent screen and the response produced on approval,
  refusal, and a malformed request. The request is injected through a launch argument (DEBUG
  builds only): `XCUIApplication.open(_:)` delivers the URL on some iOS versions and merely
  launches the app on others, and these tests are not about URL routing
- `EndToEndRPTests` — covers the real `openid:` route. It follows a link in the RP served from
  `rp/` in Safari, hands off to the app, and checks that the issued token reaches the RP and
  verifies (needs the RP server running)

## TODO

- `request` / `request_uri` support (Request Object, alg none / RS256). Until then the metadata
  sets `request_parameter_supported` and `request_uri_parameter_supported` to false — the latter
  defaults to true when omitted, so silence would advertise it
- Returning standard claims according to the `claims` parameter
- A history of previously approved RPs
