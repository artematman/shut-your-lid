#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
OUT=${1:-"${TMPDIR:-/tmp}/ShutYourLid-release"}
ID=com.artemkharitonov.shutyourlid
IDENTITY=${LID_SIGN_IDENTITY:-'Developer ID Application: Artem Kharitonov (8XZ7Z4UR6C)'}
swift build --package-path "$ROOT" --scratch-path "$OUT/build" -c release --arch arm64 --arch x86_64 \
    -Xswiftc -debug-prefix-map -Xswiftc "$ROOT=/src/shut-your-lid" \
    -Xswiftc -file-prefix-map -Xswiftc "$ROOT=/src/shut-your-lid"
BIN=$(swift build --package-path "$ROOT" --scratch-path "$OUT/build" -c release --arch arm64 --arch x86_64 --show-bin-path)
APP="$OUT/Shut Your Lid.app"
C="$APP/Contents"
mkdir -p "$C/MacOS" "$C/Resources" "$C/Library/LaunchDaemons"
cp "$BIN/ShutYourLid" "$C/MacOS/ShutYourLid"
cp "$BIN/LidPowerHelper" "$C/MacOS/LidPowerHelper"
sed -e "s/__LABEL__/$ID.power/g" -e "s/__APP_ID__/$ID/g" "$ROOT/App/power.plist.template" > "$C/Library/LaunchDaemons/$ID.power.plist"
/usr/bin/swift "$ROOT/Scripts/make-icon.swift" "$OUT/AppIcon.iconset" "$ROOT/App/Assets/LogoDark.png"
iconutil -c icns "$OUT/AppIcon.iconset" -o "$C/Resources/ShutYourLidLips.icns"
python3 - "$C/Info.plist" <<'PY'
import plistlib,sys
with open(sys.argv[1],'wb') as f:
 plistlib.dump(dict(CFBundleIdentifier='com.artemkharitonov.shutyourlid',CFBundleName='Shut Your Lid',CFBundleDisplayName='Shut Your Lid',CFBundleExecutable='ShutYourLid',CFBundleVersion='15',CFBundleShortVersionString='0.3.8',CFBundleDevelopmentRegion='en',CFBundleLocalizations=['en','ru'],CFBundlePackageType='APPL',CFBundleIconFile='ShutYourLidLips.icns',LSMinimumSystemVersion='14.0',LSUIElement=True,NSHighResolutionCapable=True),f)
PY
/usr/bin/strip -S "$C/MacOS/ShutYourLid" "$C/MacOS/LidPowerHelper"
python3 "$ROOT/Scripts/privacy-gate.py" --app "$APP"
xattr -cr "$APP"
codesign --force --options runtime --timestamp --sign "$IDENTITY" --identifier "$ID.power" "$C/MacOS/LidPowerHelper"
xattr -cr "$APP"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
xattr -dr com.apple.provenance "$APP" 2>/dev/null || true
python3 "$ROOT/Scripts/verify-app.py" "$APP"
printf '%s\n' "$APP"
