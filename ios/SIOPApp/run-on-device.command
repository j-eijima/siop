#!/bin/zsh
# Builds SIOPApp, installs it on a connected iPhone or iPad, and launches it.
#
# Double-click this in Finder. It has to run from your own GUI session: a
# non-GUI shell cannot get the keychain to release the signing key, and
# codesign fails with errSecInternalComponent.
#
# The password is read here and used only to unlock the login keychain. It is
# not stored or echoed.
set -eu
cd "$(dirname "$0")"

TEAM=BU84RDJKC6
BUNDLE_ID=jp.co.pendako.siop
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

printf 'Mac のパスワード: '
read -rs PASSWORD
printf '\n'

security unlock-keychain -p "$PASSWORD" "$KEYCHAIN"
# Once per keychain: lets codesign use the key without a GUI prompt.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASSWORD" "$KEYCHAIN" > /dev/null
unset PASSWORD

DEVICE=$(xcrun devicectl list devices 2>/dev/null | awk '/available/ {print $3; exit}')
if [ -z "$DEVICE" ]; then
    echo "接続されている端末が見つかりません。" >&2
    read -r '?Enter で閉じる'
    exit 1
fi
echo "端末: $DEVICE"

xcodegen generate
xcodebuild -project SIOPApp.xcodeproj -scheme SIOPApp \
    -destination "id=$DEVICE" -derivedDataPath .build-device \
    DEVELOPMENT_TEAM="$TEAM" build

APP=.build-device/Build/Products/Debug-iphoneos/SIOPApp.app
xcrun devicectl device install app --device "$DEVICE" "$APP"
xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE_ID"

echo
echo "インストールと起動が終わりました。"
echo "初回は iPad の 設定 > 一般 > VPN とデバイス管理 で開発元を信頼してください。"
read -r '?Enter で閉じる'
