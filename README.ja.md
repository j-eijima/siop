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

push しようとしているコミットに対して Codex の adversarial review を実行し、承認が出ない限り
push を拒否する pre-push フックを入れる。ローカルの Codex CLI を各自の認証情報で動かすため
CI では動かせず、フックを入れたマシンからの push しか守れない。フックは clone に含まれないので
clone ごとに一度実行する。個別に無視する場合は `git push --no-verify`。

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
