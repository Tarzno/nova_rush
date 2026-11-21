#!/bin/zsh
# Builds the app and packs it into the release disk image
# dist/Nova-Rush-<version>-macos-arm64.dmg (version from Support/Info.plist,
# 1.0.0 → 1.0; no spaces, which GitHub turns into dots in release file names):
# a window with the backdrop from Tools/dmgbackground.swift, the app next to
# an Applications shortcut.
#
# Finder itself lays the window out (it is scripted via osascript), so a
# Finder window briefly opens, and macOS may ask once for permission to
# control Finder. What Finder stores depends on how the Finder of the moment
# is set, so the stored layout is checked afterwards (and icons Finder moved
# are put back) with Finder looking away.
#
# Adapted from Rosettica's script, including its Finder workarounds.
set -euo pipefail
cd "$(dirname "$0")/.."

VOLUME="Nova Rush"
APP="Nova Rush.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Support/Info.plist)
[[ "$VERSION" == *.*.0 ]] && VERSION=${VERSION%.0}
DMG="dist/Nova-Rush-${VERSION}-macos-arm64.dmg"

if [[ -e "/Volumes/$VOLUME" ]]; then
    echo "error: a volume named \"$VOLUME\" is mounted — eject it first" >&2
    exit 1
fi

# The window layout (icon places, sizes): Tools/dmgbackground.swift is the
# one place it is written down, so picture and window cannot drift apart.
eval "$(swift Tools/dmgbackground.swift --layout)"

Scripts/build-app.sh
codesign --verify --deep --strict "dist/$APP"
ARCHS=$(lipo -archs "dist/$APP/Contents/MacOS/NovaRush")
if [[ "$ARCHS" != "arm64" ]]; then
    echo "error: the app is built for \"$ARCHS\", not for arm64 alone" >&2
    exit 1
fi

# Under /tmp, not the per-user temporary folder: Finder's alias to the
# backdrop records the path of the writable image, and that path ships.
WORK=$(mktemp -d /tmp/nova-rush-dmg.XXXXXX)
MOUNT=""
cleanup() {
    [[ -n "$MOUNT" ]] && hdiutil detach "$MOUNT" -quiet -force 2>/dev/null || true
    rm -rf "$WORK"
}
trap cleanup EXIT

# Backdrop at 1x and 2x in one TIFF, so it is sharp on Retina displays.
swift Tools/dmgbackground.swift "$WORK/background.png" 1
swift Tools/dmgbackground.swift "$WORK/background@2x.png" 2
tiffutil -cathidpicheck "$WORK/background.png" "$WORK/background@2x.png" \
    -out "$WORK/background.tiff" 2>/dev/null

STAGE="$WORK/stage"
mkdir -p "$STAGE/.background"
ditto "dist/$APP" "$STAGE/$APP"
ln -s /Applications "$STAGE/Applications"
cp "$WORK/background.tiff" "$STAGE/.background/background.tiff"

# A writable image first: Finder stores the window layout inside the volume.
SIZE=$(( $(du -sm "$STAGE" | cut -f1) + 20 ))
hdiutil create -quiet -srcfolder "$STAGE" -volname "$VOLUME" -fs HFS+ \
    -format UDRW -size "${SIZE}m" "$WORK/rw.dmg"
MOUNT=$(hdiutil attach "$WORK/rw.dmg" -readwrite -noverify -noautoopen 2>/dev/null \
    | awk -F'\t' '/\/Volumes\// { print $NF }')

# The volume icon is there before Finder lays the window out, so its hidden
# file gets a place too (it is copied again afterwards, see below).
cp "dist/$APP/Contents/Resources/AppIcon.icns" "$MOUNT/.VolumeIcon.icns"
SetFile -a C "$MOUNT"

# Order matters. The first time the window is reopened after its settings
# changed, Finder (seen on macOS 27) moves every icon 36 points down. So the
# window is set up and reopened *before* the icons are placed. The hidden
# files get places below the picture, for anybody whose Finder shows them
# (if Finder can script them at all; it is not an error if not).
osascript <<OSA
tell application "Finder"
    tell disk "$VOLUME"
        open
        delay 1
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        try
            set pathbar visible of container window to false
        end try
        set the bounds of container window to {200, 120, $((200 + WIN_W)), $((120 + WIN_H + 28))}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to $ICON
        set text size of viewOptions to $TEXT
        set label position of viewOptions to bottom
        set shows icon preview of viewOptions to true
        set shows item info of viewOptions to false
        set background picture of viewOptions to file ".background:background.tiff"
        close
        open
        delay 1
        set position of item "$APP" of container window to {$APP_X, $APP_Y}
        set position of item "Applications" of container window to {$APPS_X, $APPS_Y}
        set k to 0
        repeat with hiddenName in {".background", ".VolumeIcon.icns", ".fseventsd", ".Trashes"}
            try
                set position of item hiddenName of container window to {$APP_X + 140 * k, $HIDDEN_Y}
            end try
            set k to k + 1
        end repeat
        close
        open
        delay 1
        set the bounds of container window to {200, 120, $((200 + WIN_W)), $((120 + WIN_H + 28))}
        update without registering applications
        delay 2
        close
    end tell
end tell
OSA

# Finder writes the layout lazily; do not unmount before it is on disk.
for _ in {1..20}; do
    [[ -s "$MOUNT/.DS_Store" ]] && break
    sleep 0.5
done
[[ -s "$MOUNT/.DS_Store" ]] || { echo "error: Finder did not save the window layout" >&2; exit 1; }

# The volume shows the app's icon on the desktop and in Finder's sidebar
# (after Finder is done: its "update" can take a volume icon away again).
cp "dist/$APP/Contents/Resources/AppIcon.icns" "$MOUNT/.VolumeIcon.icns"
SetFile -a C "$MOUNT"
rm -rf "$MOUNT/.fseventsd" "$MOUNT/.Trashes"
sync
hdiutil detach "$MOUNT" -quiet
MOUNT=""

# Check what Finder stored, mounted where Finder does not look, and put back
# any icon it moved.
mkdir "$WORK/mnt"
hdiutil attach "$WORK/rw.dmg" -readwrite -noverify -noautoopen -nobrowse \
    -mountpoint "$WORK/mnt" -quiet 2>/dev/null
MOUNT="$WORK/mnt"
swift Tools/dmgbackground.swift --check "$MOUNT" --fix
rm -rf "$MOUNT/.fseventsd"
sync
hdiutil detach "$MOUNT" -quiet
MOUNT=""

# The release: compressed (LZMA, macOS 10.15 and later) and read-only.
rm -f "$DMG"
hdiutil convert -quiet "$WORK/rw.dmg" -format ULMO -o "$DMG"
hdiutil verify -quiet "$DMG"
echo "Built $DMG ($(du -h "$DMG" | cut -f1 | tr -d ' '))"
shasum -a 256 "$DMG"
