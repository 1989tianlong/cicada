#!/usr/bin/env bash
# Generates build/device/Cicada.xcodeproj for installing the iOS app on a physical iPhone/iPad
# from Xcode (automatic signing with your Apple ID; a free account re-signs every 7 days).
#   scripts/make-device-project.sh
# Requires xcodegen (brew install xcodegen) and Xcode. The generated project is not committed;
# the committed parts are this script and scripts/device-project.yml. The sources match
# ios/scripts/build.sh exactly (same shared-sources.txt rules and Info.plists).
set -euo pipefail
cd "$(dirname "$0")/.."

command -v xcodegen >/dev/null || { echo "xcodegen missing: brew install xcodegen" >&2; exit 1; }

STAGE=build/device/Resources
rm -rf "$STAGE" build/device/plists
mkdir -p "$STAGE" build/device/plists
# Build settings like INFOPLIST_FILE are resolved against SRCROOT (build/device/), so stage copies.
cp ios/Resources/Info.plist build/device/plists/App-Info.plist
cp ios/LiveActivity/Info.plist build/device/plists/Live-Info.plist
# UI text is the Mac's: the Chinese source is the key, the other languages translate it.
for d in Resources/*.lproj; do
  mkdir -p "$STAGE/$(basename "$d")"
  cp "$d/Localizable.strings" "$STAGE/$(basename "$d")/" 2>/dev/null || true
done
cp -R "$STAGE/zh-Hans.lproj" "$STAGE/zh-Hant.lproj"
cp Resources/sample/sample.m4a "$STAGE/"
cp -R Resources/models/SpeakerEmbedding.mlpackage "$STAGE/"
# The logo on the 听会议室 card, drawn by the app's own icon tool. The same 1024 master
# becomes the iOS home-screen icon (single-size AppIcon, asset catalog below).
LOGO_TOOL=$(swift build -c release --product CicadaIcon >/dev/null 2>&1 && swift build -c release --show-bin-path)/CicadaIcon
ICONS=$(mktemp -d)
"$LOGO_TOOL" "$ICONS/logo.iconset" >/dev/null
cp "$ICONS/logo.iconset/icon_128x128@2x.png" "$STAGE/logo.png"
mkdir -p "$STAGE/Assets.xcassets/AppIcon.appiconset"
cat > "$STAGE/Assets.xcassets/Contents.json" <<'JSON'
{ "info" : { "author" : "xcode", "version" : 1 } }
JSON
cat > "$STAGE/Assets.xcassets/AppIcon.appiconset/Contents.json" <<'JSON'
{
  "images" : [
    {
      "filename" : "icon_1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON
cp "$ICONS/logo.iconset/icon_512x512@2x.png" "$STAGE/Assets.xcassets/AppIcon.appiconset/icon_1024.png"
rm -rf "$ICONS"

# xcodegen resolves the spec's relative paths against the spec's own directory, so run it on a
# root-level copy (git-ignored via *.gen.yml) rather than on the committed scripts/ spec.
cp scripts/device-project.yml device-project.gen.yml
xcodegen --spec device-project.gen.yml --project build/device
rm -f device-project.gen.yml
echo "Next: open build/device/Cicada.xcodeproj in Xcode, pick your iPhone, press Run."
