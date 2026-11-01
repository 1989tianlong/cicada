#!/usr/bin/env bash
# Builds build/LiveSubs.app (Apple silicon).
# Without RELEASE=1 it is a dev build: "Live Subs Dev", bundle id com.wquguru.cicada.dev (its own
# settings, permissions and meeting records), stamped with the branch and commit, which show in the
# menu bar and panel; its icon carries a "DEV" band. RELEASE=1 builds the real com.wquguru.cicada.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product LiveSubs
swift build -c release --product LiveSubsIcon
BIN=$(swift build -c release --show-bin-path)

APP=build/LiveSubs.app
ICONSET=build/AppIcon.iconset
rm -rf "$APP" "$ICONSET"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN/LiveSubs" "$APP/Contents/MacOS/LiveSubs"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/sample/sample.mp4 Resources/sample/sample.m4a "$APP/Contents/Resources/"

PLIST="$APP/Contents/Info.plist"
if [[ "${RELEASE:-}" != 1 ]]; then
  STAMP="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo local) @ $(git rev-parse --short HEAD 2>/dev/null || echo none)"
  [[ -n "$(git status --porcelain --untracked-files=no 2>/dev/null)" ]] && STAMP+="+"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.wquguru.cicada.dev" \
    -c "Set :CFBundleName Live Subs Dev" -c "Set :CFBundleDisplayName Live Subs Dev" \
    -c "Add :LiveSubsDev string $STAMP" "$PLIST"
fi
if [[ -n "${BUILD_NUMBER:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"
fi

ICON_FLAGS=()
[[ "${RELEASE:-}" == 1 ]] || ICON_FLAGS=(--dev)
"$BIN/LiveSubsIcon" ${ICON_FLAGS[@]+"${ICON_FLAGS[@]}"} "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# A fixed designated requirement (the bundle id alone), so rebuilding keeps the system-audio and
# microphone permissions instead of asking again after every build.
ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$PLIST")
codesign --force --sign - --requirements "=designated => identifier \"$ID\"" "$APP" >/dev/null
echo "Built $APP ($ID)"
