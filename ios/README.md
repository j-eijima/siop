# SIOP - iOS 実装

OpenID Connect Core 1.0 7章 Self-Issued OpenID Provider (SIOP) の Swift 実装。

## SIOPKit

コアロジックの Swift Package。外部依存なし(Security / CryptoKit のみ)。

```
cd SIOPKit
swift build   # ビルド
swift test    # ユニットテスト(macOS 上で実行可)
```

### 仕様との対応

| 仕様 | 実装 |
|---|---|
| 7.1 Discovery(静的メタデータ) | `SelfIssuedMetadata` |
| 7.2 Registration(client_id = redirect_uri) | `AuthorizationRequest` の検証 |
| 7.3 Request の解析・検証 | `AuthorizationRequest(url:)` |
| 7.4 Response(Self-Issued ID Token 発行) | `SelfIssuedOP.handle(url:)` / `SelfIssuedIDToken` |
| 7.5 RP 側の ID Token 検証 | `SelfIssuedIDTokenValidator` |
| RFC 7638 JWK Thumbprint(`sub` 値) | `RSAPublicJWK.thumbprint()` |

- 署名は仕様必須の RS256(RSA 2048bit)
- 鍵は `SecKeyProvider.loadOrCreate(tag:)` で Keychain に永続化(`sub` をデバイス内で安定させる)。テストでは `generate()` の一時鍵を使用

### 使い方

```swift
let key = try SecKeyProvider.loadOrCreate(tag: "jp.example.siop.key")
let op = SelfIssuedOP(keyProvider: key)
let response = try op.handle(url: incomingOpenIDURL)  // openid://?response_type=id_token&...
// response.redirectURL を開いて RP に id_token をフラグメントで返す
```

## TODO

- `openid://` カスタム URL スキームを受けるアプリシェル(SwiftUI)
- request / request_uri(Request Object、alg none / RS256)対応
- claims パラメータに応じた標準クレームの応答
