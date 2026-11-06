#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/Always Online.app"
STAGING="$DIST/.dmg-staging"
VOLUME_NAME="Always Online"

if ! command -v hdiutil >/dev/null 2>&1; then
    printf 'Error: hdiutil is required (run this script on macOS).\n' >&2
    exit 1
fi

"$ROOT/scripts/build-app.sh"

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
DMG="$DIST/Always-Online-$VERSION.dmg"

rm -rf "$STAGING"
mkdir -p "$STAGING"
trap 'rm -rf "$STAGING"' EXIT HUP INT TERM

ditto "$APP" "$STAGING/Always Online.app"
ln -s /Applications "$STAGING/Applications"

# The mounted image carries the same icon as the app. Finder may show this
# volume icon after the image is mounted.
cp "$APP/Contents/Resources/AlwaysOnline.icns" "$STAGING/.VolumeIcon.icns"

rm -f "$DMG"
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING" \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG"

printf 'Created: %s\n' "$DMG"
printf 'The app is ad-hoc signed; distribution does not require an Apple Developer account.\n'
printf 'On first launch, macOS may require Control-click > Open because the app is not notarized.\n'
