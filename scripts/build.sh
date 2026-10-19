#!/bin/sh
# Compile en release (binaire universel arm64 + x86_64) et assemble build/ClaudeNotch.app,
# signée ad hoc.
#
# VERSION=1.2.3 scripts/build.sh  → version injectée dans la copie de l'Info.plist
# (CFBundleShortVersionString et CFBundleVersion). Par défaut : celle de Resources/Info.plist.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

PLIST_SRC="$ROOT/Resources/Info.plist"
VERSION=${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST_SRC")}
case "$VERSION" in
    '' | *[!0-9.]* | .* | *. | *..*)
        echo "VERSION invalide : « $VERSION » (attendu : 1, 1.2 ou 1.2.3)" >&2
        exit 1
        ;;
esac

ARCHS="--arch arm64 --arch x86_64"
# shellcheck disable=SC2086
swift build -c release $ARCHS
# shellcheck disable=SC2086
BIN="$(swift build -c release $ARCHS --show-bin-path)/ClaudeNotch"

for arch in arm64 x86_64; do
    if ! lipo "$BIN" -verify_arch "$arch"; then
        echo "Architecture $arch absente de $BIN ($(lipo -archs "$BIN"))" >&2
        exit 1
    fi
done

APP="$ROOT/build/ClaudeNotch.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ClaudeNotch"
cp "$PLIST_SRC" "$APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$VERSION" "$APP/Contents/Info.plist"
cp "$ROOT/hooks/claude-notch-hook.sh" "$APP/Contents/Resources/claude-notch-hook.sh"
chmod 755 "$APP/Contents/Resources/claude-notch-hook.sh"

codesign --force --deep --sign - "$APP"
echo "App prête : $APP (version $VERSION, $(lipo -archs "$APP/Contents/MacOS/ClaudeNotch"))"
