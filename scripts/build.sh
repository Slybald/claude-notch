#!/bin/sh
# Compile en release (binaire universel arm64 + x86_64) et assemble build/ClaudeNotch.app.
#
# Signature : ad hoc par défaut (le cdhash change à chaque build, macOS redemande alors les autorisations).
# SIGN_KEYCHAIN=<trousseau> SIGN_IDENTITY=<nom ou empreinte du certificat> scripts/build.sh → signature avec ce
# certificat : l'exigence désignée ne dépend plus du build, macOS garde les autorisations d'une version à l'autre.
# Les deux variables vont ensemble (la CI de release les pose, voir .github/workflows/release.yml). Pas de
# hardened runtime : il imposerait des entitlements et bloquerait le code chargé par des processus tiers
# (mediaremote-adapter, chargé par perl).
#
# VERSION=1.2.3 scripts/build.sh  → version injectée dans la copie de l'Info.plist
# (CFBundleShortVersionString et CFBundleVersion). Par défaut : celle de Resources/Info.plist.
# RELEASE_CHANNEL=1 scripts/build.sh → ClaudeNotchUpdateChannel = release : l'app se met à jour seule depuis
# les releases GitHub. Sans (builds locaux, scripts/install.sh) : aucune mise à jour automatique.
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

if [ -n "${SIGN_KEYCHAIN:-}" ] && [ -n "${SIGN_IDENTITY:-}" ]; then
    SIGNATURE="signature stable"
elif [ -z "${SIGN_KEYCHAIN:-}${SIGN_IDENTITY:-}" ]; then
    SIGNATURE="signature ad hoc"
else
    echo "SIGN_KEYCHAIN et SIGN_IDENTITY vont ensemble : définis les deux ou aucune." >&2
    exit 1
fi

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
CHANNEL=développement
if [ "${RELEASE_CHANNEL:-}" = 1 ]; then
    plutil -replace ClaudeNotchUpdateChannel -string release "$APP/Contents/Info.plist"
    CHANNEL=release
fi
cp "$ROOT/hooks/claude-notch-hook.sh" "$APP/Contents/Resources/claude-notch-hook.sh"
chmod 755 "$APP/Contents/Resources/claude-notch-hook.sh"
# Traductions (en.lproj, fr.lproj) : macOS affiche le français sur un système en français, l'anglais ailleurs.
for LPROJ in "$ROOT"/Resources/*.lproj; do
    plutil -lint -s "$LPROJ"/*.strings
    cp -R "$LPROJ" "$APP/Contents/Resources/"
done

if [ "$SIGNATURE" = "signature stable" ]; then
    codesign --force --deep --sign "$SIGN_IDENTITY" --keychain "$SIGN_KEYCHAIN" "$APP"
else
    codesign --force --deep --sign - "$APP"
fi
echo "App prête : $APP (version $VERSION, canal $CHANNEL, $(lipo -archs "$APP/Contents/MacOS/ClaudeNotch"), $SIGNATURE)"
