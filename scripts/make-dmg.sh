#!/bin/sh
# Crée build/ClaudeNotch-<version>.dmg à partir de build/ClaudeNotch.app (lancer scripts/build.sh avant),
# le vérifie (hdiutil verify, montage en lecture seule) et écrit son SHA-256 dans <dmg>.sha256.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP="$ROOT/build/ClaudeNotch.app"
VOLUME="Claude Notch"

if [ ! -d "$APP" ]; then
    echo "App introuvable : $APP (lance d'abord scripts/build.sh)" >&2
    exit 1
fi
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
DMG="$ROOT/build/ClaudeNotch-$VERSION.dmg"

STAGING=$(mktemp -d "${TMPDIR:-/tmp}/claude-notch-dmg.XXXXXX")
MOUNT=""
cleanup() {
    if [ -n "$MOUNT" ]; then
        hdiutil detach -quiet "$MOUNT" 2>/dev/null || hdiutil detach -quiet -force "$MOUNT" 2>/dev/null || true
        rmdir "$MOUNT" 2>/dev/null || true
    fi
    rm -rf "$STAGING"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

# 1. Contenu : l'app et un lien vers /Applications (racine lisible par tous, mktemp la crée en 700).
chmod 755 "$STAGING"
ditto "$APP" "$STAGING/ClaudeNotch.app"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG" "$DMG.sha256"
hdiutil create -quiet -volname "$VOLUME" -srcfolder "$STAGING" -fs HFS+ -format UDZO \
    -imagekey zlib-level=9 -ov "$DMG"

# 2. Vérifications.
hdiutil verify -quiet "$DMG"
MOUNT=$(mktemp -d "${TMPDIR:-/tmp}/claude-notch-mount.XXXXXX")
hdiutil attach -quiet -nobrowse -readonly -noautoopen -mountpoint "$MOUNT" "$DMG"
fail() {
    echo "DMG invalide : $1" >&2
    exit 1
}
[ -x "$MOUNT/ClaudeNotch.app/Contents/MacOS/ClaudeNotch" ] || fail "ClaudeNotch.app absente ou incomplète"
[ -L "$MOUNT/Applications" ] || fail "lien Applications absent"
[ "$(readlink "$MOUNT/Applications")" = /Applications ] || fail "le lien Applications ne pointe pas vers /Applications"
codesign --verify --deep --strict "$MOUNT/ClaudeNotch.app" || fail "signature de l'app invalide"
echo "Contenu vérifié : ClaudeNotch.app ($(lipo -archs "$MOUNT/ClaudeNotch.app/Contents/MacOS/ClaudeNotch")), Applications -> /Applications"
hdiutil detach -quiet "$MOUNT"
rmdir "$MOUNT"
MOUNT=""

# 3. Empreinte, au format de `shasum -a 256 -c`.
(cd "$(dirname "$DMG")" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
echo "DMG prêt : $DMG ($(du -h "$DMG" | cut -f1 | tr -d ' '))"
echo "SHA-256 : $(cut -d' ' -f1 "$DMG.sha256")"
