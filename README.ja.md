# SIOP

[English](README.md) | **日本語**

OpenID Connect Core 1.0 [7章 Self-Issued OpenID Provider](https://openid-foundation-japan.github.io/openid-connect-core-1_0.ja.html#SelfIssued)
のリファレンス実装。

Self-Issued OpenID Provider (SIOP) は、認証サーバを置かずに端末自身が OpenID Provider として
振る舞う仕組み。端末が持つ鍵で自分に対して ID Token を発行し、その公開鍵を `sub_jwk` として
トークンに同梱する。識別子 `sub` はその公開鍵の JWK サムプリント (RFC 7638) なので、
第三者の登録も発行も要らずに、鍵の持ち主であることだけを RP に示せる。

各 OS のデファクト言語で実装し、共通の RP で相互に検証する。

## 作るもの

- SIOP を利用するための SDK(ドキュメント込み)
- 実稼働するサンプルアプリ

## 何をするものか

アプリが約束する振る舞いと、どこまでできたら受け入れかは、ここではなく
[docs/specs/](docs/specs/) にある。識別子の管理と選択、署名の前にユーザーが必ず見るもの、
両側でプロトコルの各パラメータと出どころを読めるようにすること。SIOP アプリの部分は
iOS アプリが実装している。プラットフォームごとの現状は各仕様書にある。

すでに下した決定の理由 — RP ごとの鍵、Request Object を否定したこと、ブラウザ内だけで検証すること —
は [docs/decisions/](docs/decisions/) に番号付きの記録として置き、コーディングエージェントの
スキルに目次を持たせて、作業に関係するものだけを読み込ませる。

操作できる [HTML UI モック](rp/public/mock.html)で、識別子の管理・選択、応答のプレビュー、
RP でのパラメータ比較と検証を試せる。ファイルをブラウザで開くか、テスト RP の `/mock.html` に
アクセスする。一時的なメモリ上の鍵で実際の WebCrypto 処理を行い、外部 RP には送信しない。
再読み込みすると識別子は消える。モック自体はデモであり、相互運用テストではない。SIOP 側は
iOS と Android のアプリが、RP 側はテスト RP が実装している。

## 実装状況

下の順に実装する。各 OS はデファクト言語を第一に採用し、クロスプラットフォーム言語は
オプショナルで追加する。

| 順 | | 言語 | 状態 |
|---|---|---|---|
| 1 | [ios/](ios/) | Swift | ✅ SIOPKit(コア)+ SIOPApp(`openid:` を受けるアプリ) |
| 2 | [android/](android/) | Kotlin | ✅ siopkit(コア)+ app(`openid:` を受けるアプリ) |
| 3 | `cross_platform/flutter/` | Dart | 未着手 |
| 4 | `windows/` | C# | 未着手 |
| 5 | `macos/` | Swift | 未着手 |
| 6 | `cross_platform/rust/` | Rust | 未着手 |
| 7 | `linux/` | — | 未着手 |
| — | [rp/](rp/) | JavaScript | ✅ 全実装共通のテスト用 Relying Party |

## 仕様との対応

| 仕様 | 内容 |
|---|---|
| 7.1 Discovery | 静的メタデータ。`authorization_endpoint` は `openid:`、署名は RS256 |
| 7.2 Registration | 登録手続きが無く、RP は redirect URI をそのまま `client_id` として使う |
| 7.3 Request | `openid://` で受け取る認証リクエスト |
| 7.4 Response | `iss` = `https://self-issued.me`、`sub` = `sub_jwk` のサムプリント |
| 7.5 Validation | RP 側での iss / sub / sub_jwk / 署名 / aud / nonce の検証 |

## 動かす

```
# テスト RP を起動 (http://localhost:8080/)
python3 rp/serve.py

# iOS: SIOPKit のユニットテスト
cd ios/SIOPKit && swift test

# iOS: アプリと end-to-end テスト (RP の起動が前提)
cd ios/SIOPApp && xcodegen generate
xcodebuild -project SIOPApp.xcodeproj -scheme SIOPApp \
  -destination 'platform=iOS Simulator,name=iPhone 17' test

# RP の検証ロジック (Node だけで動く)
cd rp && node --test
```

シミュレータ名は手元の Xcode にあるものを指定する。`iPhone 17` は例。

## 実装間の一致をどう確かめるか

実装が増えるほど、各実装が「自分の中では正しい」状態に留まりやすくなる。それを防ぐため、
検証は必ず別の実装に渡して行う。

- `rp/test/verify.test.mjs` — Swift (SIOPKit) が署名した実物の ID Token を JavaScript が検証する。
  トークンはフィクスチャとしてコミットしてあるので、Swift の無い環境でも走る
- `rp/test/cross-implementation.test.mjs` — 同じ検証をその時点の Swift ビルドの出力に対して行い、
  フィクスチャが古くなって後退を見逃すのを防ぐ(Swift が無ければ自動でスキップ)
- `ios/SIOPApp/UITests/EndToEndRPTests.swift` — Safari 上の RP からアプリを起動し、
  発行されたトークンが RP で検証されるまでを通す
- `ios/SIOPKit` の `siop-issue` CLI が、任意のリクエストに対するトークンを吐く。
  他言語の実装を足すときは、まずこの CLI の出力を自分の検証器に通すところから始められる

新しい実装を追加するときは、`rp/` の RP で認証が通ることをもって最低限の適合とする。

## push の前に

```
tools/install-hooks.sh
```

以下の方針で動作する pre-push フックを入れる。

| push 元 | レビュー |
|---|---|
| Claude Code | Codex の adversarial review。承認が必要 |
| Codex | レビューなし (通常・adversarial ともに実行しない) |

Codex は `CODEX_THREAD_ID` または `CODEX_SESSION_ID`、Claude Code は
[`CLAUDECODE=1`](https://code.claude.com/docs/en/env-vars) で検出する。明示的な `PUSH_AGENT` を
優先する。通常のターミナルから実行する場合や、エージェントの入れ子で両方の情報が残る場合は、
適用する方針を指定する。

```sh
PUSH_AGENT=codex git push   # レビューなし
PUSH_AGENT=claude git push # Codex がレビュー
```

push 元が不明・曖昧な場合は拒否する。この情報は方針の選択に使い、コミットの作成者を証明する
ものではない。Codex からの push はスキップをログに表示し、companion プラグインも不要。
ブランチ削除と変更のない ref はレビュー・push 元の検出ともに不要。

Claude Code からの push は、正常に完了した Codex レビューの構造化された `approve` だけを
通す。実行失敗・解析できない結果・レビュアの未導入では拒否する。レビュアはベースと
チェックアウト中の HEAD を比較するので、このレビュー経路では HEAD の fast-forward と、
送信先が広告するベースのある新規ブランチだけが対象になる。`tools/test-pre-push.sh` が
振り分け・スキップ・レビューの拒否条件を、レビュアをスタブ化した使い捨てリポジトリで検査する。

ローカルの Codex CLI を各自の認証情報で動かすためレビューは CI では動かせず、フックを
入れたマシンだけが対象になる。フックは clone に含まれないので clone ごとに一度インストーラを
実行する。個別に意図して無視する場合は `git push --no-verify`。

このゲートにプロジェクト固有の部分は無い。他で使うときは `tools/hooks/`、
`tools/install-hooks.sh`、`tools/test-pre-push.sh` をコピーすればよく、スクリプトには git・node・sh
が必要。Claude Code からのレビュー経路には、認証済みの Codex CLI と companion プラグインも
必要。companion は `CODEX_COMPANION`、Git config の `codex.companion` の順に優先し、
指定がなければ `~/.claude/plugins/cache/openai-codex/codex/*/scripts/codex-companion.mjs` の
導入済み最新版を使う。

## ドキュメント

対応自然言語は英語と日本語。自身を説明するディレクトリにはそれぞれ `README.md` と
`README.ja.md` を置き、互いにリンクする。英語版を正とし、先に英語を直してから同じコミットで
日本語を直す。片方だけ変更しない。

```
python3 tools/check-docs.py
```

翻訳が同じことを言っているかは人が判断するしかないが、対が崩れる壊れ方は機械的なので、
CI で検査して強制する — 片方が無い、片方にだけ節が増えた、言語切り替えリンクが無い、
相対リンクが切れている。

コーディングエージェントの設定はドキュメントではないので対象外
(ローカルの `CLAUDE.md` は ignore し、`.claude/` は検査しない。`.gitignore` や `project.yml` を
翻訳しないのと同じ)。`docs/specs/` の仕様書はドキュメントなので、他と同じに検査する。
