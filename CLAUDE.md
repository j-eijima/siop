# OpenID Connect Core 仕様 7章 Self-Issued Identity Provider(SIOP)のリファレンス実装プロジェクト
https://openid-foundation-japan.github.io/openid-connect-core-1_0.ja.html#SelfIssued

このファイルはコーディングエージェントへの指示であり、プロジェクトのドキュメントではない。
そのため「対応自然言語」のルールの対象外とし、日本語のみで書く。
ここに要件を書き足したら、人が読む形は README.md / README.ja.md に反映すること。

# アウトプット
- SIOPを利用するためのSDK
  - ドキュメント
- 実稼働するサンプルアプリ

# 対応自然言語
- 英語
- 日本語
※各種ドキュメント(*.md)は対応言語すべてで作成すること(このファイルを除く。冒頭を参照)

# 対応OS
- iOS
- Android
- Windows
- Mac OS

# プログラミング言語
実装OSごとのデファクト言語を第一に採用し実装

クロスプラットフォーム言語はオプショナルで採用し実装（Flutter(iOS/Androidクロスプラットフォーム、Rust(Winodws/Mac OSクロスプラットフォーム))

# 実装優先順位
1. iOS
2. Android
3. Flutter
4. Windows
5. Mac OS
6. Rust
7. Linux

# ディレクトリ構成
+ siop
  + ios
  + android
  + windows
  + macos
  + linux
  + cross_platform
    + flutter
    + rust
  + rp
  - CLAUDE.md

rp は各OS実装の動作確認に使う、SIOP 対応のテスト用 Relying Party(OS 横断)。
