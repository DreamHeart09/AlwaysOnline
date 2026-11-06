#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP="$ROOT/dist/Always Online.app"
STAGE="$ROOT/dist/.Always Online.building.app"
CACHE="/tmp/always-online-module-cache"
ICONSET="/tmp/always-online.iconset"
mkdir -p "$ROOT/dist" "$CACHE"
rm -rf "$STAGE" "$ICONSET"
mkdir -p "$ICONSET" "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
swiftc -module-cache-path "$CACHE" scripts/render-brand.swift -o /tmp/always-online-render-brand
/tmp/always-online-render-brand
cp Resources/Brand/AlwaysOnline-AppIcon-Preview.png Resources/Assets.xcassets/AlwaysOnline.appiconset/AlwaysOnline-AppIcon-1024.png
for size in 128 256 512 1024; do
    sips -z "$size" "$size" Resources/Brand/AlwaysOnline-AppIcon-Preview.png --out "$ICONSET/$size.png" >/dev/null
done
python3 - "$ICONSET" "$STAGE/Contents/Resources/AlwaysOnline.icns" <<'PY'
import pathlib, struct, sys
src, dest = map(pathlib.Path, sys.argv[1:])
chunks = [(b'ic07',128),(b'ic08',256),(b'ic09',512),(b'ic10',1024)]
body = bytearray()
for tag, size in chunks:
    image = (src / f'{size}.png').read_bytes()
    body += tag + struct.pack('>I', len(image) + 8) + image
dest.write_bytes(b'icns' + struct.pack('>I', len(body) + 8) + body)
PY
cp Resources/Brand/AlwaysOnline-MenuBar.png "$STAGE/Contents/Resources/AlwaysOnline-MenuBar.png"
swiftc -parse-as-library -module-cache-path "$CACHE" App/AlwaysOnline.swift -o "$STAGE/Contents/MacOS/AlwaysOnline"
cat > "$STAGE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>AlwaysOnline</string>
<key>CFBundleIconFile</key><string>AlwaysOnline</string>
<key>CFBundleIdentifier</key><string>local.alwaysonline.mvp</string>
<key>CFBundleName</key><string>Always Online</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$STAGE"
codesign --verify --deep --strict "$STAGE"
plutil -lint "$STAGE/Contents/Info.plist"
rm -rf "$APP"
mv "$STAGE" "$APP"
printf 'Built and verified: %s\n' "$APP"
