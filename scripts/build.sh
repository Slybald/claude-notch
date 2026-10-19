#!/bin/sh
# Compile en release et assemble build/ClaudeNotch.app (signature ad hoc).
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

swift build -c release
BIN_DIR=$(swift build -c release --show-bin-path)

APP="$ROOT/build/ClaudeNotch.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/ClaudeNotch" "$APP/Contents/MacOS/ClaudeNotch"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/hooks/claude-notch-hook.sh" "$APP/Contents/Resources/claude-notch-hook.sh"
chmod 755 "$APP/Contents/Resources/claude-notch-hook.sh"

codesign --force --sign - "$APP"
echo "App prête : $APP"
