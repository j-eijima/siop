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
| pairwise な sub(7.1 `subject_types_supported`) | `SIOPKeyStore`。`client_id` ごとの鍵 |

- 署名は仕様必須の RS256(RSA 2048bit)
- 鍵は RP ごとに分ける。メタデータが広告するとおり本当に pairwise になり、2つの RP が同じ
  利用者だと突き合わせることはできない。`KeychainKeyStore` が `client_id` から Keychain の
  タグを導出するので、同じ RP には毎回同じ識別子を提示する。テストや CLI では
  `EphemeralKeyStore` がメモリ上に鍵を持つ
- 鍵は利用者が応答したときに作る。リクエストが届いただけでは作らない。`client_id` は送信側が
  決められるので、表示時に作ると未応答のリクエストで Keychain が埋まり、RSA 生成で画面が
  止まる。同意画面は、確立済みなら識別子を、未確立なら新しく作る旨を表示する
- 単一鍵だった頃のバージョンから更新すると、識別子は変わる。旧鍵は全 RP で共有されていた
  ため、引き継げば pairwise が取り除こうとしている紐付け可能性ごと引き継ぐことになる。移行
  経路は用意しない。`sub` でアカウントを識別する RP からは別人に見える

### 使い方

```swift
let keys = KeychainKeyStore(tagPrefix: "jp.example.siop.key")
let op = SelfIssuedOP(keyStore: keys)
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
   拒否時は Section 3.1.2.6 に従い `#error=access_denied` を返す。Section 7.2 では `client_id`
   に任意の URI を書けるため、端末に開けるアプリが無い場合もある。その場合は届いたことに
   せず、渡せなかったと表示する

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

- `AuthenticationSessionTests` — 応答を渡している最中の挙動が対象。画面の話ではなく状態の話
  なのでここに置く。配送中は同意画面が消えること、開けない redirect が報告されること、新しい
  リクエストの後に届いた完了がそれを上書きしないこと。配送手段を注入するので割り込みの順序を
  正確に作れる
- `AuthenticationFlowUITests` — 同意画面と、承認 / 拒否 / 不正リクエストに対する応答が対象。
  リクエストは起動引数(DEBUG ビルドのみ)で直接渡す。`XCUIApplication.open(_:)` は iOS の
  バージョンによって URL を配送したりしなかったりするため、URL ルーティングを対象としない
  これらのテストをそこに依存させない
- `EndToEndRPTests` — 実際の `openid:` 経路が対象。Safari 上の `rp/` からリンクをたどって
  アプリを起動し、発行されたトークンが RP で検証されるまでを通す(RP サーバの起動が前提)

## TODO

- request / request_uri(Request Object、alg none / RS256)対応。それまではメタデータで
  `request_parameter_supported` と `request_uri_parameter_supported` を false にする。後者は
  省略時 true が既定なので、書かないと広告したことになる
- claims パラメータに応じた標準クレームの応答
- 承認済み RP の履歴表示
