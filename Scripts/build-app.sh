#!/bin/zsh
# Builds the release binary and assembles a standard macOS app bundle.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

# The License window shows a copy of the license compiled into the binary;
# never ship a bundle whose copy differs from the LICENSE file.
if ! .build/release/NovaRush --license | diff -q - LICENSE >/dev/null; then
    echo "error: LICENSE differs from License.text in Sources/NovaRush/License.swift" >&2
    exit 1
fi

APP="dist/Nova Rush.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Support/Info.plist "$APP/Contents/"
cp .build/release/NovaRush "$APP/Contents/MacOS/"
if [ -d .build/release/NovaRush_NovaRush.bundle ]; then
    cp -R .build/release/NovaRush_NovaRush.bundle "$APP/Contents/Resources/"
fi
if [ -f Support/AppIcon.icns ]; then
    cp Support/AppIcon.icns "$APP/Contents/Resources/"
fi
codesign --force --sign - "$APP"
echo "Built $APP"
