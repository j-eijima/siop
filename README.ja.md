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

## UI の予定要件

SIOP アプリ・RP ともに、プロトコルのパラメータを分かりやすく理解できることを最優先にする。
実際の値、その出どころ、リクエスト・応答・検証の期待値の対応関係を表示する。
以下は UI の要件であり、実装済みの機能ではない。

SIOP アプリでは、識別子(`sub` と対応する鍵)の作成・一覧と詳細の閲覧・編集・削除を行え、
応答ごとにどの識別子を使うか選択できるようにする。署名前に、選択した `sub`、
公開鍵(`sub_jwk`)、応答先を表示する。識別子と RP の対応も明示する。
現在の実装は RP ごとに別の鍵を自動で使うため、識別子の明示的な管理・選択にはこの動作の拡張が必要。

`sub` は公開鍵から導出され、自由に編集できる文字列ではない。編集 UI 案ではローカルの表示名や
メモを変更し、鍵の変更は別の `sub` の作成として扱う。削除時は、署名鍵を削除すると鍵を復元できない限り
その識別子で再び応答できなくなることと、RP 側のアカウントを削除する操作ではないことを説明する。

操作できる [HTML UI モック](rp/public/mock.html)で、識別子の管理・選択、応答のプレビュー、
RP でのパラメータ比較と検証を試せる。ファイルをブラウザで開くか、テスト RP の `/mock.html` に
アクセスする。一時的なメモリ上の鍵で実際の WebCrypto 処理を行い、外部 RP には送信しない。
再読み込みすると識別子は消える。これは UI のデモであり、ネイティブアプリへの機能実装や
相互運用テストではない。

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

push しようとしているコミットを、もう一方のコーディングエージェントで cross-check する
pre-push フックを入れる。

| push 元 | レビュア |
|---|---|
| Claude Code | Codex |
| Codex | Claude Code |

どちらも構造化された判定を返す adversarial review を実行する。正常に完了したレビューの
`approve` だけが push を通す。実行失敗・解析できない結果・レビュアの未導入では拒否し、
push 元と同じエージェントには切り替えない。Claude companion の通常の `review` は構造化された
判定ではなく文章を返すため、このゲートでは両側とも `adversarial-review` を使う。

Codex は `CODEX_THREAD_ID` または `CODEX_SESSION_ID`、Claude Code は
[`CLAUDECODE=1`](https://code.claude.com/docs/en/env-vars) で検出する。明示的な `PUSH_AGENT` を
優先する。通常のターミナルから実行する場合や、エージェントの入れ子で両方の情報が残る場合は、
push 元を指定する。

```sh
PUSH_AGENT=codex git push   # Claude Code がレビュー
PUSH_AGENT=claude git push # Codex がレビュー
```

push 元が不明・曖昧な場合は拒否する。これは実行環境からレビュアを選ぶ仕組みであり、
コミットの作成者を証明するものではない。

ローカルのレビュア CLI を各自の認証情報で動かすため CI では動かせず、フックを入れたマシン
だけが対象になる。フックは clone に含まれないので clone ごとに一度インストーラを実行する。
個別に意図して無視する場合は `git push --no-verify`。

レビュアはベースとチェックアウト中の HEAD を比較するため、現在のブランチの fast-forward しか
判断できない。それ以外 — force push、チェックアウトしていない ref、リモートにレビュー済みの
起点が無い新規ブランチ — は、カバーできていないレビューで承認せずに拒否する。この判断は
`tools/test-pre-push.sh` がレビュアをスタブ化した使い捨てリポジトリで検査する。ゲートの壊れ方は
「レビューされないものを通してしまう」ことなので。

このゲートにプロジェクト固有の部分は無い。他で使うときは `tools/hooks/`、
`tools/install-hooks.sh`、`tools/test-pre-push.sh` をコピーすればよく、必要なのは git・node・sh
だけ。レビュアの CLI と companion プラグインの導入・認証も必要。companion の場所は以下の
優先順位で決める。

| レビュア | 環境変数で指定 | Git config | 既定のプラグインキャッシュ |
|---|---|---|---|
| Codex | `CODEX_COMPANION` | `codex.companion` | `~/.claude/plugins/cache/openai-codex/codex/*/scripts/codex-companion.mjs` |
| Claude Code | `CLAUDE_COMPANION` | `claude.companion` | `$CODEX_HOME/plugins/cache/sendbird/cc/*/scripts/claude-companion.mjs` |

Claude companion の探索で `CODEX_HOME` が未設定の場合は `~/.codex` を使う。既定の探索は
導入済みの最新版を選ぶので、プラグイン更新後に古いバージョンを参照し続けない。
配置が異なる場合は環境変数か Git config で指定する。

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
(ローカルの `CLAUDE.md` は ignore している。`.gitignore` や `project.yml` を翻訳しないのと同じ)。
