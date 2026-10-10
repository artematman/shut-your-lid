#!/bin/sh
# Run after building (and, for a public release, notarizing/stapling) the app.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
APP=${1:?"Usage: package-release.sh /path/to/app /path/to/output"}
OUT=${2:?"Specify the release output directory"}
IDENTITY=${LID_SIGN_IDENTITY:-'Developer ID Application: Artem Kharitonov (8XZ7Z4UR6C)'}
python3 "$ROOT/Scripts/verify-app.py" "$APP"
mkdir -p "$OUT"
STAGE=$(mktemp -d /private/tmp/shutyourlid-dmg.XXXXXX)
trap 'rm -rf "$STAGE"' EXIT HUP INT TERM
/usr/bin/ditto "$APP" "$STAGE/Shut Your Lid.app"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/READ ME.txt" <<'TXT'
Shut Your Lid 0.3.9 — signed release candidate
Drag the app to Applications and launch it. Approve its own background helper in macOS Login Items & Extensions when requested.
This app was accepted by Apple notarization and stapled. Clean-system helper and hardware acceptance remain pending; this is not a stable release. Do not bypass Gatekeeper. Never put a working MacBook in a bag.
TXT
/usr/bin/ditto -c -k --keepParent "$APP" "$OUT/Shut-Your-Lid-0.3.9-universal.zip"
python3 "$ROOT/Scripts/privacy-gate.py" --zip "$OUT/Shut-Your-Lid-0.3.9-universal.zip"
hdiutil create -volname 'Shut Your Lid' -srcfolder "$STAGE" -format UDZO -ov "$OUT/Shut-Your-Lid-0.3.9-universal.dmg"
codesign --force --timestamp --sign "$IDENTITY" "$OUT/Shut-Your-Lid-0.3.9-universal.dmg"
codesign --verify --strict "$OUT/Shut-Your-Lid-0.3.9-universal.dmg"
