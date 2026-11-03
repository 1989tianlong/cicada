#!/usr/bin/env bash
# Prints the release notes for one version: its CHANGELOG.md section, a compare link to the version
# below it, the Chinese changelog on the website, then .github/release-notes.md.
# scripts/release_notes.sh 1.0.0
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=${1:?usage: scripts/release_notes.sh <version>}
awk -v v="$VERSION" '
  /^## / { on = ($2 == v) ; next }
  on { print }
' CHANGELOG.md | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}'
PREV=$(awk -v v="$VERSION" '/^## / { if (seen) { print $2; exit } if ($2 == v) seen = 1 }' CHANGELOG.md)
echo
echo "---"
echo
[[ -n "$PREV" ]] && echo "**Full changelog**: https://github.com/wquguru/cicada/compare/v$PREV...v$VERSION" && echo
echo "中文更新说明：https://cicada.indaloop.app/changelog/"
echo
cat .github/release-notes.md
