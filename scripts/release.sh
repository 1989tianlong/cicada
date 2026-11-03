#!/usr/bin/env bash
# Cuts a release: scripts/release.sh 1.0.1
# Writes the CHANGELOG.md section from the commits since the last tag, sets the version in
# Resources/Info.plist, commits, tags v<version> and pushes; the release workflow builds and
# publishes the DMG with that section as its notes.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${1:?usage: scripts/release.sh <version, e.g. 1.0.1>}
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "version must look like 1.2.3" >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "working tree is not clean" >&2; exit 1; }
[[ "$(git branch --show-current)" == main ]] || { echo "release from main" >&2; exit 1; }
git rev-parse "v$VERSION" >/dev/null 2>&1 && { echo "tag v$VERSION already exists" >&2; exit 1; }
# The CHANGELOG.md section comes from the feat:/fix: commits since the last tag (scripts/changelog.py);
# a section already dated today, written by hand, is kept as it is.
if ! grep -q "^## $VERSION — $(date +%Y-%m-%d)" CHANGELOG.md; then
  scripts/changelog.py "$VERSION"
  git commit -m "docs: changelog for $VERSION" CHANGELOG.md
fi

CURRENT=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
if [[ "$CURRENT" != "$VERSION" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Resources/Info.plist
  git commit -m "chore: release v$VERSION" Resources/Info.plist
fi
git tag -a "v$VERSION" -m "Cicada $VERSION"
git push origin main "v$VERSION"
echo "Pushed v$VERSION; follow it at https://github.com/wquguru/cicada/actions/workflows/release.yml"
