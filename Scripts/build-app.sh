#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
OUT=${1:-"${TMPDIR:-/tmp}/ShutYourLid-release"}
ID=com.artemkharitonov.shutyourlid
IDENTITY='Developer ID Application: Artem Kharitonov (8XZ7Z4UR6C)'
swift build --package-path "$ROOT" -c release \
    -Xswiftc -debug-prefix-map -Xswiftc "$ROOT=/src/shut-your-lid" \
    -Xswiftc -file-prefix-map -Xswiftc "$ROOT=/src/shut-your-lid"
BIN=$(swift build --package-path "$ROOT" -c release --show-bin-path)
APP="$OUT/Shut Your Lid.app"
C="$APP/Contents"
mkdir -p "$C/MacOS" "$C/Resources" "$C/Library/LaunchDaemons"
cp "$BIN/ShutYourLid" "$C/MacOS/ShutYourLid"
cp "$BIN/LidPowerHelper" "$C/MacOS/LidPowerHelper"
sed -e "s/__LABEL__/$ID.power/g" -e "s/__APP_ID__/$ID/g" "$ROOT/App/power.plist.template" > "$C/Library/LaunchDaemons/$ID.power.plist"
/usr/bin/swift "$ROOT/Scripts/make-icon.swift" "$ROOT/.build-app/AppIcon.iconset"
iconutil -c icns "$ROOT/.build-app/AppIcon.iconset" -o "$C/Resources/AppIcon.icns"
python3 - "$C/Info.plist" <<'PY'
import plistlib,sys
with open(sys.argv[1],'wb') as f:
 plistlib.dump(dict(CFBundleIdentifier='com.artemkharitonov.shutyourlid',CFBundleName='Shut Your Lid',CFBundleDisplayName='Shut Your Lid',CFBundleExecutable='ShutYourLid',CFBundleVersion='2',CFBundleShortVersionString='0.2.0',CFBundlePackageType='APPL',CFBundleIconFile='AppIcon',LSMinimumSystemVersion='14.0',LSUIElement=True,NSHighResolutionCapable=True),f)
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
