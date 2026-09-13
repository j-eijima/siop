# SIOP テスト RP

[English](README.md) | **日本語**

Self-Issued OpenID Provider (OpenID Connect Core 1.0 7章) の動作確認用 Relying Party。

認証リクエストを組み立てて OP に渡し、返ってきた ID Token を Section 7.5 の手順で検証する。
検証は WebCrypto を使ってブラウザ内で完結する — Implicit Flow の応答は URL のフラグメントで
返り、フラグメントはサーバに送信されないため、ID Token がサーバに渡ることはない。

## 起動

```
python3 serve.py            # http://localhost:8080/
python3 serve.py --tls      # https://<この Mac の LAN アドレス>:8443/
python3 serve.py --port 9000
```

静的ファイルを配るだけで、依存パッケージは無い。

検証は WebCrypto で行うが、これは secure context でしか使えない。`http://localhost` は該当するが
LAN アドレスの平文 HTTP は該当しないため、LAN 越しに開いた端末ではページは表示されても検証は
できない。

`--tls` は自己署名証明書で HTTPS を提供する。デスクトップのブラウザなら警告を押し進められるので
これで足りる。**iOS では足りない** — Safari は信頼できない証明書を押し進める手段ごと拒否するため、
ページ自体が開かない。iPhone / iPad で検証まで通すには、証明書を端末に入れて信頼させるか、実際の
証明書を持つ場所に RP を置くかのどちらかになる。ワイルドカード DNS で名前を付けても解決しない —
secure context の判定はスキームであって名前ではない。

## 使い方

1. `http://localhost:8080/` を開く
2. パラメータを必要に応じて編集する(既定値は仕様に沿った最小構成)
3. 「SIOP で識別子を選択 →」で `openid://...` を開く
4. OP が `redirect_uri` のフラグメントに応答を載せて戻ってくると、この RP が送った値と返ってきた
   値が並び、検査ごとの判定が表示される

ページはブラウザの言語に合わせる — 英語か、ブラウザが日本語を優先していれば日本語。ヘッダの
切り替えか、URL の `?lang=en` / `?lang=ja` で変えられ、このブラウザに記憶される。切り替えは
その場で描き直すので、照合済みの結果は失われない。

### リクエストは編集できる

すべてのパラメータを書き換えられ、追加もできる。仕様から外れた値は「仕様との差分」に警告として
出るが、送信は止めない — OP が不正なリクエストをどう扱うかを確かめるのが目的なので、
`response_type=code` や nonce 無しをそのまま送れる。

各パラメータには根拠となる章番号を添えてある。応答と照合するもの — `client_id`・`nonce`・`state` —
には印を付け、RP が照合用に控える値としても並べる。応答側も、受け取ったフラグメントの各パラメータを
同じ形式で並べる。

### 照合の違いを試す

届いたトークンは変えられないが、RP が期待する値は変えられる。検証結果の画面では、同じトークンを
別の `nonce`・`state`・`aud` で照合し直せるので、ひとつの検査が失敗し、残りは通ったまま表示される
ところを確かめられる。トークン自体には手を付けない。

## 検証項目 (Section 7.5)

| 項目 | 内容 |
|---|---|
| JWS 形式 | 3 セグメントに分解でき、ヘッダとペイロードが JSON として読める |
| alg | `RS256`(7.1 で必須とされる署名アルゴリズム) |
| iss | `https://self-issued.me` |
| sub_jwk | RSA 公開鍵が含まれる |
| sub | `sub_jwk` の JWK サムプリント (RFC 7638) と一致する |
| 署名 | `sub_jwk` の鍵で検証できる |
| aud | この RP の `client_id` 宛て |
| nonce | リクエストで送った値と一致する |
| state | フラグメントの `state` が送った値と一致する — トークンには含まれないので、トークンとは別に照合する |
| exp | 期限内 |

失敗しても最初の項目で止めず、全項目の結果を一覧で出す。

## テスト

```
node --test
```

Node だけあれば動く。依存パッケージは無い。

- `test/verify.test.mjs` — Swift (`ios/SIOPKit`) が署名した実物の ID Token
  (`test/fixtures/swift-issued.json`)を検証する。改竄・aud 不一致・nonce 不一致・
  期限切れが正しく弾かれることも確認する
- `test/cross-implementation.test.mjs` — 同じ検証を、**その時点の** Swift ビルドが発行した
  トークンに対して行う。フィクスチャが古くなって相互運用性の後退を見逃すのを防ぐ。
  Swift が無い環境では自動でスキップされる
- `test/state.test.mjs` — トークンの外側で行う `state` の照合
- `test/request.test.mjs` — リクエストそのものに対する仕様の規則。3.2.2.1 が http の
  `redirect_uri` を許すのはネイティブアプリだけで、ホストも仕様が挙げる3つ — `localhost`・
  `127.0.0.1`・`[::1]` — に限られる。この RP は Web ページなので、自分の既定値にも警告を出す

フィクスチャの更新は `test/fixtures/regenerate.sh`(Swift が必要)。

iOS アプリまで含めた end-to-end テストは
`ios/SIOPApp/UITests/EndToEndRPTests.swift`(このサーバの起動が前提)。

## ホスティング

サーバは `$PORT` からポートを受け取り、ページは読み込まれた URL から `client_id` と
`redirect_uri` を導出する。TLS を終端してポートを渡す環境なら設定なしで動く。`Dockerfile` が
そのままイメージになる。

```
gcloud run deploy siop-rp --source rp --allow-unauthenticated
```

スマホやタブレットで試すなら、ホストしてしまうのが現実的。証明書が端末の信頼済みのものになる。

## 既知の制約

- **既定のブラウザで開くこと。** OP は `redirect_uri` を開いて応答を返すが、iOS は https を
  既定ブラウザに渡すため、リクエストを始めたブラウザに戻す方法が無い。別のブラウザで始めると
  応答が届かず、nonce / state を保持している localStorage も参照できないため照合に失敗する
  (誤って成功する方向には倒れない)。
- **既定の `redirect_uri` 自体が仕様の外にある。** 3.2.2.1 は Implicit Flow での http を、
  ネイティブアプリが localhost・ループバックアドレスを使う場合を除いて禁じている。この RP は
  Web ページなので、`http://localhost:8080/callback.html` はその例外に入らない。リクエスト画面は
  毎回そう警告する。仕様どおりに試すには、RP を https でホストする。
- 検証には secure context が要るので、LAN アドレスの平文 http ではページは開いても検証できない。
  デスクトップのブラウザなら `--tls` で足りるが、iOS では足りず、RP をホストするか証明書を端末に
  信頼させる必要がある。
