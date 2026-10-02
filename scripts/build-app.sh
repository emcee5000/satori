#!/bin/bash
# Builds a release Satori.app in ./build. Pass --install to copy it to /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Satori.app"
VERSION="$(cat VERSION)"

# A universal binary runs natively on both Apple silicon and Intel Macs. Each
# architecture is built separately and merged, which needs only the Command Line Tools.
BIN="build/Satori-universal"
mkdir -p build
SLICES=()
for ARCH in arm64 x86_64; do
    echo "→ Compiling for $ARCH (release)…"
    swift build -c release --triple "$ARCH-apple-macosx14.0"
    SLICES+=("$(swift build -c release --triple "$ARCH-apple-macosx14.0" --show-bin-path)/Satori")
done
lipo -create "${SLICES[@]}" -output "$BIN"

echo "→ Assembling bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
mv "$BIN" "$APP/Contents/MacOS/Satori"

ICONSET="build/Satori.iconset"
rm -rf "$ICONSET"
swift scripts/make-icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Satori</string>
    <key>CFBundleDisplayName</key><string>Satori</string>
    <key>CFBundleIdentifier</key><string>io.github.emcee5000.satori</string>
    <key>CFBundleExecutable</key><string>Satori</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null
echo "✓ Built $APP ($(du -sh "$APP" | cut -f1))"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf /Applications/Satori.app
    cp -R "$APP" /Applications/
    echo "✓ Installed to /Applications/Satori.app"
fi
