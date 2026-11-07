#!/usr/bin/env bash
# Builds the website and deploys it to the Cloudflare Worker "cicada-site" (static assets only), which
# serves cicada.indaloop.app. The custom domain is attached to the Worker in Cloudflare, so the config
# below declares no routes and a deploy leaves it alone. Needs `wrangler login` once.
set -euo pipefail
cd "$(dirname "$0")/.."

# A version dated in site/changelog.json shows as released, and scripts/release.sh dates it in the
# release commit, before the draft is published: don't put it on the site until then.
dated=$(python3 -c 'import json; print(next(e["version"] for e in json.load(open("site/changelog.json")) if e.get("date")))')
[[ "$(gh release view "v$dated" -R wquguru/cicada --json isDraft -q .isDraft 2>/dev/null)" == false ]] ||
  { echo "v$dated is not published yet: deploy the site after scripts/publish-release.sh" >&2; exit 1; }
python3 scripts/site.py
CONFIG=$(mktemp -d)
trap 'rm -rf "$CONFIG"' EXIT
cat > "$CONFIG/wrangler.jsonc" <<JSON
{
  "name": "cicada-site",
  "compatibility_date": "2026-10-01",
  "assets": { "directory": "$PWD/build/site", "html_handling": "auto-trailing-slash" }
}
JSON
(cd "$CONFIG" && wrangler deploy --config wrangler.jsonc)
curl -fsS -o /dev/null "https://cicada.indaloop.app/?deployed=$(date +%s)" && echo "Live: https://cicada.indaloop.app/"
