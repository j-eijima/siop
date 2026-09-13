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
| Pairwise subjects (7.1 `subject_types_supported`) | `SIOPIdentityStore` — identities, each bound to one `client_id` |

- Signing is RS256 with a 2048-bit RSA key, which the spec requires
- An identity is a key and the names the user gives it, bound to one `client_id` for good
  (`SIOPIdentity`). One RP may have several; no identity ever answers a second RP, so the subject
  really is pairwise as the metadata says: two RPs cannot tell they are talking to the same
  person. `SIOPIdentityStore.keychain(tagPrefix:)` keeps keys and their records together in the
  Keychain; `.ephemeral()` keeps them in memory for tests
- A key is created only by the user: creating an identity, or answering an RP that has none.
  Never when a request merely arrives — `client_id` comes from whoever sent the request, so
  allocating on display would let unanswered requests fill the Keychain and stall on RSA
  generation
- Keys made by the key-per-RP version (`KeychainKeyStore`) are taken over as identities the first
  time their RP asks again, so the subject that RP already knows is kept. `SIOPKeyStore` remains
  for tools such as `siop-issue`, where nobody chooses anything
- Devices that ran the earlier single-key version present new subjects: the old key was shared
  across RPs, and any scheme that preserved it would preserve the linkability that pairwise keys
  exist to remove. There is no migration, and RPs that key accounts on `sub` will see a new user

### Using it

```swift
let identities = SIOPIdentityStore.keychain(tagPrefix: "jp.example.siop.key")
let request = try AuthorizationRequest(url: incomingOpenIDURL)  // openid://?response_type=id_token&...
// Offer identities(for:) to choose from. Make a new one only once the user has said to answer
let identity = try identities.identities(for: request.clientID).first
    ?? identities.createIdentity(for: request.clientID)
let response = try SelfIssuedOP.respond(to: request, signingWith: try identities.keyProvider(for: identity))
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

The screens follow the [UI mock](../rp/public/mock.html); what they must do is in
[docs/specs/](../docs/specs/). The app follows the device language — English, or Japanese where
the device prefers it — with English as the source in `SIOPApp/Sources/Localizable.xcstrings`.

1. **Identities** — every identity on the device, grouped by the RP it answers, and the
   Discovery metadata. Opening one shows its `sub`, its RP, its public key and the JSON the
   thumbprint is taken over. The names can be changed and the identity deleted; the `sub` cannot
   be edited
2. **Consent** — shown on receiving `openid://...`, in three parts. The request as it arrived,
   every parameter in order, with the requester (`client_id` = `redirect_uri`) labelled as
   unverified, since a SIOP cannot authenticate the RP. The identities for this RP, to choose
   between or add to. And a preview of every value that will be signed, each marked by where it
   comes from — copied from the request, taken from the chosen key, or fixed — with `state` shown
   apart, since it travels outside the token
3. **Response** — approving signs as the chosen identity, or as a new one for this RP when it has
   none, and opens `redirect_uri#id_token=...&state=...`. Refusing returns `#error=access_denied`,
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

- `AuthenticationSessionTests` — covers state rather than any screen. While a response is being
  delivered: the consent screen is gone, a redirect nothing opens is reported, and a completion
  arriving after a newer request cannot replace it. For identities: a request or a refusal creates
  none, the first answer creates exactly one, the response is signed as the identity chosen, an
  identity never answers another RP, and renaming keeps the `sub`. Delivery and the store are
  injected, so both are exact
- `AuthenticationFlowUITests` — covers the consent screen, creating and deleting an identity, and
  the response produced on approval, refusal, and a malformed request. Buttons are found by
  accessibility identifier, since the approve button's title depends on whether the RP has an
  identity yet. The rest is read as text, so the app is launched in English
  (`-AppleLanguages (en)`) whatever language the simulator is set to. The request is injected through a launch argument (DEBUG
  builds only): `XCUIApplication.open(_:)` delivers the URL on some iOS versions and merely
  launches the app on others, and these tests are not about URL routing
- `EndToEndRPTests` — covers the real `openid:` route. It follows a link in the RP served from
  `rp/` in Safari, hands off to the app, and checks that the issued token reaches the RP and
  verifies (needs the RP server running). The RP is opened with `?lang=en`, since Safari follows
  the simulator's language

## TODO

- `request` / `request_uri` support (Request Object, alg none / RS256). Until then the metadata
  sets `request_parameter_supported` and `request_uri_parameter_supported` to false — the latter
  defaults to true when omitted, so silence would advertise it
- Returning standard claims according to the `claims` parameter
