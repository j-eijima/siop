# SIOP - iOS 実装

[English](README.md) | **日本語**

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

## SIOPApp

`openid:` 認証エンドポイントを受け取る SwiftUI アプリ。プロジェクトは XcodeGen で
`project.yml` から生成する(`.xcodeproj` は生成物なので Git 管理外)。

```
cd SIOPApp
xcodegen generate
xcodebuild -project SIOPApp.xcodeproj -scheme SIOPApp \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

### 画面と流れ

1. **識別子画面** — この端末が提示する `sub`(JWK サムプリント)、公開鍵、Discovery メタデータ
2. **同意画面** — `openid://...` を受け取ると表示。要求元(`client_id` = `redirect_uri`)、
   要求 scope、`nonce` / `state` を提示する。SIOP は RP を認証できないため、要求元 URL は
   「検証されていない」と明示している
3. **応答** — 承認で ID Token を発行し `redirect_uri#id_token=...&state=...` を開く。
   拒否時は Section 3.1.2.6 に従い `#error=access_denied` を返す

### RP と合わせた動作確認

`rp/` のテスト RP を起動すると、リクエスト送信から ID Token の検証まで一通り試せる。

```
python3 ../rp/serve.py     # 別ターミナルで
```

### 単体での動作確認

```
xcrun simctl openurl booted "openid://?response_type=id_token\
&client_id=https%3A%2F%2Fclient.example.org%2Fcb&scope=openid%20profile\
&state=af0ifjsldkj&nonce=n-0S6_WzA2Mj"
```

### テストの分担

- `AuthenticationFlowUITests` — 同意画面と、承認 / 拒否 / 不正リクエストに対する応答が対象。
  リクエストは起動引数(DEBUG ビルドのみ)で直接渡す。`XCUIApplication.open(_:)` は iOS の
  バージョンによって URL を配送したりしなかったりするため、URL ルーティングを対象としない
  これらのテストをそこに依存させない
- `EndToEndRPTests` — 実際の `openid:` 経路が対象。Safari 上の `rp/` からリンクをたどって
  アプリを起動し、発行されたトークンが RP で検証されるまでを通す(RP サーバの起動が前提)

## TODO

- request / request_uri(Request Object、alg none / RS256)対応
- claims パラメータに応じた標準クレームの応答
- 承認済み RP の履歴表示
