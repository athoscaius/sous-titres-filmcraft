#!/bin/zsh
set -euo pipefail
PACKAGE_DIR="${0:A:h}"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/artcraft-subtitles-package.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
APP="$BUILD_DIR/Sous-titres FilmCraft.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
BACKEND_CACHE="${BACKEND_CACHE:-${TMPDIR:-/tmp}/artcraft-subtitles-build-cache}" "$PACKAGE_DIR/source/backend/build-backend.command" "$APP/Contents/Resources"
xcrun swiftc -parse-as-library -D FILMCRAFT_INTEGRATION -framework AppKit -framework AVKit -framework AVFoundation -O -target arm64-apple-macos14.0 -module-cache-path "${ARTCRAFT_MODULE_CACHE:-$BUILD_DIR/swift-cache}" "$PACKAGE_DIR/source/UI/"*.swift "$PACKAGE_DIR/source/Integration/FilmCraftBridge.swift" -o "$APP/Contents/MacOS/ArtCraftSubtitlesIA"
if [[ ! -f "$PACKAGE_DIR/assets/AppIcon.icns" ]]; then zsh "$PACKAGE_DIR/source/Icon/prepare_icon.command"; fi
cp "$PACKAGE_DIR/assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon-v2.icns"
cp "$PACKAGE_DIR/assets/app-icon.png" "$APP/Contents/Resources/AppIcon-v2.png"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.artcraft.sous-titres-ia</string>
<key>CFBundleName</key><string>Sous-titres FilmCraft</string>
<key>CFBundleDisplayName</key><string>Sous-titres FilmCraft</string>
<key>CFBundleExecutable</key><string>ArtCraftSubtitlesIA</string>
<key>CFBundleIconFile</key><string>AppIcon-v2.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.3.1</string>
<key>CFBundleVersion</key><string>5</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>LSApplicationCategoryType</key><string>public.app-category.video</string>
<key>NSHumanReadableCopyright</key><string>Compagnon indépendant pour FilmCraft. Whisper et whisper.cpp sous licence MIT.</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP/Contents/Resources/bin/whisper-cli"
codesign --force --sign - "$APP/Contents/Resources/bin/transcribe"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
ditto -c -k --keepParent --noextattr --norsrc "$APP" "$PACKAGE_DIR/Sous-titres-FilmCraft-macOS-arm64.zip"
print "Archive construite : $PACKAGE_DIR/Sous-titres-FilmCraft-macOS-arm64.zip"
