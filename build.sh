#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build/module-cache
# Sign outside synced folders, which may attach FinderInfo asynchronously.
bundleRoot=$(mktemp -d /private/tmp/MacSweep-build.XXXXXX)
trap 'rm -rf "$bundleRoot"' EXIT
bundle="$bundleRoot/MacSweep.app"
mkdir -p "$bundle/Contents/MacOS"
mkdir -p "$bundle/Contents/Resources"
cp Assets/AppIcon.icns "$bundle/Contents/Resources/AppIcon.icns"
cp Sources/Resources/BrandIcon.png "$bundle/Contents/Resources/BrandIcon.png"
swiftc -swift-version 5 -target arm64-apple-macosx13.0 -O -module-cache-path build/module-cache Sources/Scanner.swift Sources/Safety.swift Sources/JunkScanner.swift Sources/MacSweep.swift -o "$bundle/Contents/MacOS/MacSweep" -framework SwiftUI -framework AppKit -framework Quartz -framework CryptoKit -framework ImageIO -framework CoreServices
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>MacSweep</string>
<key>CFBundleDisplayName</key><string>MacSweep</string>
<key>CFBundleIdentifier</key><string>local.macsweep.desktop</string>
<key>CFBundleExecutable</key><string>MacSweep</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.5</string>
<key>CFBundleVersion</key><string>6</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>CFBundleDevelopmentRegion</key><string>it</string>
<key>CFBundleLocalizations</key><array><string>it</string></array>
<key>NSDesktopFolderUsageDescription</key><string>Esamina i file della Scrivania solo quando la scegli per la scansione.</string>
<key>NSDocumentsFolderUsageDescription</key><string>Esamina i documenti solo quando scegli la cartella per la scansione.</string>
<key>NSDownloadsFolderUsageDescription</key><string>Esamina i download solo quando scegli la cartella per la scansione.</string>
</dict></plist>
PLIST
codesign --force --sign - "$bundle"
codesign --verify --deep --strict "$bundle"
ditto --norsrc --noextattr "$bundle" build/MacSweep.app
ditto -c -k --keepParent --norsrc --noextattr "$bundle" build/MacSweep.app.zip
echo "Creata: $(pwd)/build/MacSweep.app"
echo "Archivio firmato verificato: $(pwd)/build/MacSweep.app.zip"
