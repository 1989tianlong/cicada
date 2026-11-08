#!/usr/bin/env bash
# Signs the unsigned device build (make-device-project.sh + xcodebuild CODE_SIGNING_ALLOWED=NO)
# with the locally installed wildcard development profile and installs it on a connected device —
# no Xcode account login needed. Usage: scripts/sign-device.sh [device-udid]
set -euo pipefail
cd "$(dirname "$0")/.."

UDID=${1:?usage: scripts/sign-device.sh <device-udid>   # xcrun devicectl list devices}
IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/{print $2; exit}')
PROFILE=$(ls "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/"*.mobileprovision 2>/dev/null | head -1)
[[ -n "$PROFILE" ]] || { echo "no provisioning profile in Xcode UserData" >&2; exit 1; }
APP=$(find ~/Library/Developer/Xcode/DerivedData/Cicada-*/Build/Products/Debug-iphoneos \
  -maxdepth 1 -name "Cicada.app" | head -1)

cp "$PROFILE" "$APP/embedded.mobileprovision"
security cms -D -i "$PROFILE" > /tmp/prov.plist
python3 -c "
import plistlib
d = plistlib.load(open('/tmp/prov.plist','rb'))
plistlib.dump(d['Entitlements'], open('/tmp/app-ent.plist','wb'), fmt=plistlib.FMT_XML)
"
# The wildcard profile covers both the app and the Live Activity extension bundle IDs.
codesign --force --sign "$IDENTITY" --entitlements /tmp/app-ent.plist "$APP/PlugIns/CicadaLive.appex"
codesign --force --sign "$IDENTITY" --entitlements /tmp/app-ent.plist "$APP"
xcrun devicectl device install app --device "$UDID" "$APP"
echo "Launch with: xcrun devicectl device process launch --device $UDID com.1989tianlong.cicada"
