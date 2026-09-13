# SIOP — Android

[English](README.md) | **日本語**

OpenID Connect Core 1.0 7章 Self-Issued OpenID Provider の Kotlin 実装。

## siopkit

コアロジック。署名に `java.security` を使う素の JVM モジュールなので、Android SDK なしで
ビルドもテストも通る。

```
./gradlew :siopkit:test
```

### 仕様との対応

| 仕様 | 実装 |
|---|---|
| 7.1 Discovery(静的メタデータ) | `SelfIssuedMetadata` |
| 7.2 Registration(client_id = redirect_uri) | `AuthorizationRequest` の検証 |
| 7.3 リクエストの解析・検証 | `AuthorizationRequest.parse` |
| 7.4 Self-Issued ID Token の発行 | `SelfIssuedOp.respond` / `SelfIssuedIdToken` |
| 7.5 RP 側の ID Token 検証 | `SelfIssuedIdTokenValidator` |
| RFC 7638 JWK サムプリント(`sub` の値) | `RsaPublicJwk.thumbprint()` |
| pairwise な sub(7.1 `subject_types_supported`) | `SiopIdentityStore`。識別子はそれぞれ 1 つの RP 用の鍵 |

- 署名は仕様必須の RS256(RSA 2048bit)
- 識別子とは、鍵とユーザーが付けた名前の組で、生涯ひとつの `client_id` に結びつく
  ([決定 0011](../docs/decisions/0011-identities-per-rp.md))。ひとつの RP に複数持てるが、
  ひとつの識別子が別の RP に応答することはないので、sub は pairwise のまま。2つの RP が同じ
  利用者だと突き合わせることはできない。`SiopIdentityStore` が記録とその裏の鍵を持つ。
  テストでは `SiopIdentityStore.ephemeral()` がどちらもメモリ上に持つ
- 鍵を作るのは、ユーザーが RP に応答したときか識別子を作ったときだけ。リクエストが届いただけ
  では作らない。`client_id` は送信側が決められるので、表示時に作ると未応答のリクエストで
  キーストアが埋まり、RSA 生成で画面が止まる
- 読めない記録は読み飛ばさず、そこで止まる。読み飛ばすとその RP が初めての相手に見え、応答すると
  別の sub になる
- RP ごとの鍵の版(`SiopKeyStore`、`client_id` ごとに 1 つ)が作った鍵は、その RP から次に
  リクエストが来たときに識別子として引き継ぐ。その RP が知っている sub はそのまま残る。
  `SiopKeyStore` と `EphemeralKeyStore` は、誰も選ばない `siop-issue` のために残してある
- 単一鍵だった頃のバージョンから更新すると、識別子は変わる。旧鍵は全 RP で共有されていた
  ため、引き継げば pairwise が取り除こうとしている紐付け可能性ごと引き継ぐことになる。移行
  経路は用意しない

### 使い方

```kotlin
val store = SiopIdentityStore.ephemeral()
val request = AuthorizationRequest.parse(incomingOpenIdUrl)  // openid://?response_type=id_token&...
val identity = store.identitiesFor(request.clientId).firstOrNull()
    ?: store.createIdentity(request.clientId)                // ユーザーが同意してから
val response = SelfIssuedOp.respond(request, store.keyProvider(identity))
// response.redirectUrl を開いて RP に id_token をフラグメントで返す
```

## siop-issue

リクエストに対するトークンを Swift 版 `siop-issue` と同じ形式で出力する。どちらの実装の
出力も、もう一方の検証器に通せる。

```
./gradlew :siop-issue:run --args="openid://?response_type=id_token&client_id=...&scope=openid&nonce=n1"
```

## 他の実装との突き合わせ

自分で発行したトークンを自分で検証するだけでは、実装が自己完結して間違っている状態を
見逃す。そのため両方向を確認している。

- `CrossImplementationTest` — Swift が署名したトークンを、この Kotlin 検証器で検証する。
  トークンは `rp/test/fixtures/` のフィクスチャなので、ここに Swift ツールチェインは要らない
- `rp/test/verify.test.mjs` — Kotlin が署名したトークンを、RP の JavaScript 実装で検証する

フィクスチャの更新は `rp/test/fixtures/regenerate.sh`(Swift と JDK が必要)。

## app

`openid:` 認証エンドポイントを受け取る Compose アプリ。画面は [UI モック](../rp/public/mock.html)
に沿う。端末の言語に合わせて英語と日本語で表示する
([決定 0012](../docs/decisions/0012-english-and-japanese-ui.md))。

```
./gradlew :app:assembleDebug
./gradlew :app:testDebugUnitTest          # セッションを JVM で
./gradlew :app:connectedDebugAndroidTest   # エミュレータか実機が必要
```

### 画面と流れ

1. **ホーム** — 端末にある識別子を、応答する RP ごとにまとめて並べ、Discovery メタデータを示す。
   識別子を開くと、`sub`、公開鍵、サムプリントを取る JSON を見られ、名前の変更や削除ができる
2. **同意画面** — `openid://...` を受け取ると表示。届いたリクエストをそのまま示し、応答に使う
   識別子を選ぶか作らせ、公開鍵を含めて署名される値をすべて出どころ付きでプレビューする。
   青はリクエストから、緑は選んだ鍵から、灰色は固定値か署名時に決まる値。SIOP は RP を
   認証できないため、要求元 URL は「検証されていない」と明示している
3. **応答** — 承認で ID Token を発行し `redirect_uri#id_token=...&state=...` を開く。
   拒否時は Section 3.1.2.6 に従い `#error=access_denied` を返す。Section 7.2 では `client_id`
   に任意の URI を書けるため、端末に開けるアプリが無い場合もある。その場合は届いたことに
   せず、渡せなかったと表示する

鍵は Android Keystore に置く(`AndroidKeystoreIdentityKeys`)。`sub` が起動をまたいで同じになり、
秘密鍵はキーストアの外に出ない。その横の記録 — 名前、RP、最後に応答した時刻 — は、バックアップ
されない場所の JSON ファイルに置く(`FileIdentityRecords`)。鍵はキーストアから出られないので、
記録だけが復元されると、二度と応答できない識別子が並ぶことになる。アプリを消せば両方消える。

識別子を読めないときは、同意画面に進まずにそう表示して止まる。識別子はあるのに鍵を読めない
RP には、ユーザーが自分で作らない限り、新しい識別子で応答しない。

### 動作確認

```
adb shell am start -a android.intent.action.VIEW \
  -d "'openid://?response_type=id_token&client_id=https%3A%2F%2Fclient.example.org%2Fcb\
&scope=openid%20profile&state=af0ifjsldkj&nonce=n-0S6_WzA2Mj'"
```

### テスト

- `AuthenticationSessionTest`(`src/test/`)— セッションが決めることを JVM で確かめる。応答前に
  鍵を作らない、選んだ識別子で署名する、別の RP には応答しない、識別子を読めなければ止まる
- `AuthenticationFlowTest` — 画面。端末の言語によらず英語で表示して確かめる
- `AndroidIdentityStorageTest` — Keystore と記録ファイル。キーストアの中で署名したトークンが
  検証を通ること、RP ごとの鍵が引き継がれることを含む
- `EndToEndRpTest` — Chrome とテスト RP を通した往復。ホストで RP を動かし端末へ転送する必要が
  あり、無ければ自分でスキップする:

  ```
  python3 rp/serve.py
  adb reverse tcp:8080 tcp:8080
  ```

## まだ無いもの

- `request` / `request_uri`(Request Object)対応。それまではメタデータで
  `request_parameter_supported` と `request_uri_parameter_supported` を false にする。後者は
  省略時 true が既定なので、書かないと広告したことになる
- claims パラメータに応じた標準クレームの応答
