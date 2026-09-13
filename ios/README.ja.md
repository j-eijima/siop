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
| pairwise な sub(7.1 `subject_types_supported`) | `SIOPIdentityStore`。識別子はそれぞれ 1 つの `client_id` に紐づく |

- 署名は仕様必須の RS256(RSA 2048bit)
- 識別子は、鍵と利用者が付けた名前の組で、1 つの `client_id` にずっと紐づく(`SIOPIdentity`)。
  1 つの RP に複数持てるが、ひとつの識別子が別の RP に応答することはない。そのためメタデータが
  広告するとおり本当に pairwise になり、2つの RP が同じ利用者だと突き合わせることはできない。
  `SIOPIdentityStore.keychain(tagPrefix:)` は鍵とその記録をまとめて Keychain に置き、
  `.ephemeral()` はテスト用にメモリ上に置く
- 鍵を作るのは利用者だけ。識別子を作ったときか、識別子の無い RP に応答したとき。
  リクエストが届いただけでは作らない。`client_id` は送信側が決められるので、表示時に作ると
  未応答のリクエストで Keychain が埋まり、RSA 生成で画面が止まる
- RP ごとの鍵の版(`KeychainKeyStore`)が作った鍵は、その RP から次にリクエストが来たときに
  識別子として引き継ぐ。その RP がすでに知っている `sub` は変わらない。`SIOPKeyStore` は、
  誰も選択をしない `siop-issue` のようなツールのために残している
- 単一鍵だった頃のバージョンから更新すると、識別子は変わる。旧鍵は全 RP で共有されていた
  ため、引き継げば pairwise が取り除こうとしている紐付け可能性ごと引き継ぐことになる。移行
  経路は用意しない。`sub` でアカウントを識別する RP からは別人に見える

### 使い方

```swift
let identities = SIOPIdentityStore.keychain(tagPrefix: "jp.example.siop.key")
let request = try AuthorizationRequest(url: incomingOpenIDURL)  // openid://?response_type=id_token&...
// identities(for:) を選択肢として示す。新しく作るのは、利用者が応答すると決めてから
let identity = try identities.identities(for: request.clientID).first
    ?? identities.createIdentity(for: request.clientID)
let response = try SelfIssuedOP.respond(to: request, signingWith: try identities.keyProvider(for: identity))
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

画面は [UI モック](../rp/public/mock.html)に沿っている。何をすべきかは
[docs/specs/](../docs/specs/) にある。表示は端末の言語に合わせる — 英語か、端末が日本語を
優先していれば日本語。英語を原文として `SIOPApp/Sources/Localizable.xcstrings` に置いている。

1. **識別子画面** — 端末にあるすべての識別子を、応答する RP ごとにまとめて示し、Discovery
   メタデータも出す。開くと `sub`、対応する RP、公開鍵、サムプリントの計算に使う JSON を
   示す。名前は変更でき、識別子は削除できる。`sub` は編集できない
2. **同意画面** — `openid://...` を受け取ると表示。3 つの部分からなる。届いたリクエストを
   パラメータの順のまま示し、要求元(`client_id` = `redirect_uri`)は、SIOP が RP を
   認証できないため「検証されていない」と明示する。この RP 用の識別子を選ぶか、新しく作る。
   そして署名されるすべての値のプレビューを、それぞれの出どころ — リクエストから転記、
   選んだ鍵から、固定値 — とともに示す。`state` はトークンの外側で返すので別に示す
3. **応答** — 承認で、選んだ識別子で(この RP 用の識別子が無ければ新しく作って)署名し、
   `redirect_uri#id_token=...&state=...` を開く。
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

- `AuthenticationSessionTests` — 画面ではなく状態が対象。応答を渡している最中については、
  同意画面が消えること、開けない redirect が報告されること、新しいリクエストの後に届いた完了が
  それを上書きしないこと。識別子については、リクエストや拒否では作られないこと、最初の応答で
  ちょうど 1 つ作られること、選んだ識別子で署名されること、別の RP には応答しないこと、名前を
  変えても `sub` が変わらないこと。配送手段とストアを注入するので、どちらも正確に作れる
- `AuthenticationFlowUITests` — 同意画面、識別子の作成と削除、承認 / 拒否 / 不正リクエストに
  対する応答が対象。承認ボタンの文言はその RP に識別子があるかで変わるので、ボタンは
  アクセシビリティ識別子で探す。それ以外は文言で読むので、シミュレータの言語設定によらず
  アプリは英語で起動する(`-AppleLanguages (en)`)。
  リクエストは起動引数(DEBUG ビルドのみ)で直接渡す。`XCUIApplication.open(_:)` は iOS の
  バージョンによって URL を配送したりしなかったりするため、URL ルーティングを対象としない
  これらのテストをそこに依存させない
- `EndToEndRPTests` — 実際の `openid:` 経路が対象。Safari 上の `rp/` からリンクをたどって
  アプリを起動し、発行されたトークンが RP で検証されるまでを通す(RP サーバの起動が前提)。Safari はシミュレータの言語に従うので、RP は `?lang=en` で開く

## TODO

- request / request_uri(Request Object、alg none / RS256)対応。それまではメタデータで
  `request_parameter_supported` と `request_uri_parameter_supported` を false にする。後者は
  省略時 true が既定なので、書かないと広告したことになる
- claims パラメータに応じた標準クレームの応答
