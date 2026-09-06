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

- Signing is RS256 with a 2048-bit RSA key, which the spec requires
- `SecKeyProvider.loadOrCreate(tag:)` persists the key in the Keychain so that `sub` stays stable
  for a given device. Tests use the ephemeral key from `generate()` instead

### Using it

```swift
let key = try SecKeyProvider.loadOrCreate(tag: "jp.example.siop.key")
let op = SelfIssuedOP(keyProvider: key)
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
   as Section 3.1.2.6 prescribes

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

- `request` / `request_uri` support (Request Object, alg none / RS256)
- Returning standard claims according to the `claims` parameter
- A history of previously approved RPs
