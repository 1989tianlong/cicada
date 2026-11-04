#!/usr/bin/env bash
# Prints the platforms one version ships, one per line (mac, windows, android, linux): those with a
# group in its CHANGELOG.md section (scripts/changelog.py). Every platform shares the version, but
# one with no feat or fix is left out of the release, so its update check finds nothing new.
# A section written by hand without platform groups (1.0.0's "### Highlights") ships the Mac app.
# scripts/release_platforms.sh 1.1.0
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=${1:?usage: scripts/release_platforms.sh <version>}
awk -v v="$VERSION" '
  /^## / { on = ($2 == v); if (on) found = 1; next }
  on && /^### (Mac|Windows|Android|Linux)$/ { print tolower($2); n++ }
  END { if (!found) exit 1; if (!n) print "mac" }
' CHANGELOG.md || { echo "no CHANGELOG.md section for $VERSION" >&2; exit 1; }
