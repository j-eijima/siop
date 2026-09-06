# SIOP — Android

[English](README.md) | **日本語**

OpenID Connect Core 1.0 7章 Self-Issued OpenID Provider の Kotlin 実装。

## siopkit

コアロジック。署名に `java.security` を使う素の JVM モジュールなので、Android SDK なしで
ビルドもテストも通る。

```
gradle :siopkit:test
```

### 仕様との対応

| 仕様 | 実装 |
|---|---|
| 7.1 Discovery(静的メタデータ) | `SelfIssuedMetadata` |
| 7.2 Registration(client_id = redirect_uri) | `AuthorizationRequest` の検証 |
| 7.3 リクエストの解析・検証 | `AuthorizationRequest.parse` |
| 7.4 Self-Issued ID Token の発行 | `SelfIssuedOp.handle` / `SelfIssuedIdToken` |
| 7.5 RP 側の ID Token 検証 | `SelfIssuedIdTokenValidator` |
| RFC 7638 JWK サムプリント(`sub` の値) | `RsaPublicJwk.thumbprint()` |

- 署名は仕様必須の RS256(RSA 2048bit)
- `KeyPairProvider` は任意の JCA 鍵ペアを受け取る。Android Keystore の鍵を渡せば `sub` が
  起動をまたいで安定する。テストでは `KeyPairProvider.generate()` の一時鍵を使う

### 使い方

```kotlin
val key = KeyPairProvider(keyPairFromAndroidKeystore)
val response = SelfIssuedOp(key).handle(incomingOpenIdUrl)  // openid://?response_type=id_token&...
// response.redirectUrl を開いて RP に id_token をフラグメントで返す
```

## siop-issue

リクエストに対するトークンを Swift 版 `siop-issue` と同じ形式で出力する。どちらの実装の
出力も、もう一方の検証器に通せる。

```
gradle :siop-issue:run --args="openid://?response_type=id_token&client_id=...&scope=openid&nonce=n1"
```

## 他の実装との突き合わせ

自分で発行したトークンを自分で検証するだけでは、実装が自己完結して間違っている状態を
見逃す。そのため両方向を確認している。

- `CrossImplementationTest` — Swift が署名したトークンを、この Kotlin 検証器で検証する。
  トークンは `rp/test/fixtures/` のフィクスチャなので、ここに Swift ツールチェインは要らない
- `rp/test/verify.test.mjs` — Kotlin が署名したトークンを、RP の JavaScript 実装で検証する

フィクスチャの更新は `rp/test/fixtures/regenerate.sh`(Swift と JDK が必要)。

## app

`openid:` 認証エンドポイントを受け取る Compose アプリ。

```
./gradlew :app:assembleDebug
./gradlew :app:connectedDebugAndroidTest   # エミュレータか実機が必要
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

署名鍵は Android Keystore に置く(`SiopKeyStore`)。`sub` が起動をまたいで同じになり、
秘密鍵はキーストアの外に出ない。

### 動作確認

```
adb shell am start -a android.intent.action.VIEW \
  -d "'openid://?response_type=id_token&client_id=https%3A%2F%2Fclient.example.org%2Fcb\
&scope=openid%20profile&state=af0ifjsldkj&nonce=n-0S6_WzA2Mj'"
```

## まだ無いもの

- `request` / `request_uri`(Request Object)対応。それまではメタデータで
  `request_parameter_supported` と `request_uri_parameter_supported` を false にする。後者は
  省略時 true が既定なので、書かないと広告したことになる
- claims パラメータに応じた標準クレームの応答
