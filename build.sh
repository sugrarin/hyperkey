#!/bin/bash
set -e
cd "$(dirname "$0")"

swift build -c release

APP="/Applications/Hyperkey.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Hyperkey "$APP/Contents/MacOS/Hyperkey"

# App icon: cache AppIcon.icns from app-icon.png using native sips/iconutil (no Pillow).
# macOS grid: content sits in an 824/1024 squircle (~80.5%), ~20% transparent padding —
# baked in here so app-icon.png stays full-bleed. Regenerates only when the PNG is newer.
SRC="app-icon.png"
if [ -f "$SRC" ] && [ "$SRC" -nt AppIcon.icns ]; then
    ICONSET=$(mktemp -d)/AppIcon.iconset
    mkdir -p "$ICONSET"
    pad() {  # pad <size> <out>: resize source to 824/1024 of size, center-pad transparent to size
        local S=$1 out=$2
        local c=$(( (S*824 + 512) / 1024 ))   # separate line: $S must be set before the arithmetic
        local t=$(mktemp -d)/c.png
        sips -z $c $c "$SRC" --out "$t" >/dev/null
        sips -c $S $S "$t"   --out "$out" >/dev/null
    }
    for s in 16 32 128 256 512; do
        pad $s       "$ICONSET/icon_${s}x${s}.png"
        pad $((s*2)) "$ICONSET/icon_${s}x${s}@2x.png"
    done
    iconutil -c icns "$ICONSET" -o AppIcon.icns   # cache at repo root
fi
[ -f AppIcon.icns ] && cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Menu-bar icon (template, recolored by macOS)
[ -f menu-icon.svg ] && cp menu-icon.svg "$APP/Contents/Resources/menu-icon.svg"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Hyperkey</string>
    <key>CFBundleDisplayName</key><string>Hyperkey</string>
    <key>CFBundleIdentifier</key><string>ee.timur.hyperkey</string>
    <key>CFBundleExecutable</key><string>Hyperkey</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
    <key>UTExportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key><string>ee.timur.hyperkey.config</string>
            <key>UTTypeDescription</key><string>Hyperkey Config</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.json</string>
            </array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>hyperkey</string>
                </array>
            </dict>
        </dict>
    </array>
</dict>
</plist>
EOF

# Sign with a stable identity so Accessibility permission survives rebuilds.
# (ad-hoc "-" changes the cdhash every build and macOS revokes the grant.)
IDENTITY=$(security find-identity -v -p codesigning | awk 'NR==1 && /\)/ {print $2}')
codesign --force --sign "${IDENTITY:--}" "$APP"

# relaunch
pkill -x Hyperkey 2>/dev/null || true
open "$APP"
echo "built + launched $APP"
