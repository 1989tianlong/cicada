#!/usr/bin/env bash
# Prints the release notes for one version: its CHANGELOG.md section, then .github/release-notes.md.
# scripts/release_notes.sh 2.0.0
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=${1:?usage: scripts/release_notes.sh <version>}
awk -v v="$VERSION" '
  /^## / { on = ($2 == v) ; next }
  on { print }
' CHANGELOG.md | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}'
echo
cat .github/release-notes.md
