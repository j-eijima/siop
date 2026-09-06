# OpenID Connect Core 仕様 7章 Self-Issued Identity Provider(SIOP)のリファレンス実装プロジェクト
https://openid-foundation-japan.github.io/openid-connect-core-1_0.ja.html#SelfIssued

# アウトプット
- SIOPを利用するためのSDK
  - ドキュメント
- 実稼働するサンプルアプリ

# 対応OS
- iOS
- Android
- Windows
- Mac OS

# 使用言語
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
  - CLAUDE.md
