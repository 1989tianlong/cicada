#!/usr/bin/env bash
# Deploys the website to Alibaba Cloud OSS static website hosting.
#   scripts/deploy-site-aliyun.sh
# Prereqs:
#   - aliyun CLI installed (brew install aliyun-cli) and configured:
#       aliyun configure set --profile default --mode AK --region "$OSS_REGION" \
#         --access-key-id <AK> --access-key-secret <SK>
#   - env vars:
#       OSS_BUCKET   bucket name (created if missing)
#       OSS_REGION   e.g. oss-cn-hangzhou; for a domain without ICP use oss-cn-hongkong
#       SITE_URL     optional; canonical URL baked into the pages
#                    (defaults to https://$OSS_BUCKET.$OSS_REGION.aliyuncs.com)
#       CUSTOM_DOMAIN  optional; also binds it to the bucket (needs CNAME at the DNS provider)
# After the first deploy, bind a custom domain via the OSS console (needs ICP filing in
# mainland regions) and rerun with SITE_URL=https://your.domain/ to bake it into the pages.
set -euo pipefail
cd "$(dirname "$0")/.."

OSS_BUCKET=${OSS_BUCKET:?set OSS_BUCKET}
# Accept both "cn-hangzhou" and "oss-cn-hangzhou": the oss commands want the endpoint
# region without the "oss-" prefix (they build <bucket>.<region>.aliyuncs.com themselves).
OSS_REGION=${OSS_REGION#oss-}
OSS_REGION=${OSS_REGION:?set OSS_REGION, e.g. cn-hangzhou or cn-hongkong}
SITE_URL=${SITE_URL:-"https://$OSS_BUCKET.$OSS_REGION.aliyuncs.com"}

command -v aliyun >/dev/null || { echo "aliyun CLI not found: brew install aliyun-cli" >&2; exit 1; }

echo "Building site for $SITE_URL …"
SITE_URL="$SITE_URL/" python3 scripts/site.py

echo "Ensuring bucket $OSS_BUCKET ($OSS_REGION) …"
aliyun oss mb "oss://$OSS_BUCKET" --region "$OSS_REGION" --acl public-read 2>/dev/null || true

echo "Enabling static website hosting (index.html) …"
WEBSITE_XML=$(mktemp /tmp/cicada-website-XXXX.xml)
cat > "$WEBSITE_XML" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<WebsiteConfiguration>
  <IndexDocument><Suffix>index.html</Suffix></IndexDocument>
  <ErrorDocument><Key>index.html</Key></ErrorDocument>
</WebsiteConfiguration>
XML
aliyun oss website --method put "oss://$OSS_BUCKET" "$WEBSITE_XML" --region "$OSS_REGION" >/dev/null || \
  echo "  (website config skipped — set it in the OSS console: 基础设置 › 静态页面)" >&2
rm -f "$WEBSITE_XML"

# Bind the custom domain when CUSTOM_DOMAIN is set (also needs a CNAME record at the DNS
# provider pointing the domain at $OSS_BUCKET.$OSS_REGION.aliyuncs.com; mainland buckets
# additionally require the domain to be ICP-filed).
if [[ -n "${CUSTOM_DOMAIN:-}" ]]; then
  echo "Binding domain $CUSTOM_DOMAIN …"
  aliyun oss bucket-cname --method put "oss://$OSS_BUCKET" "$CUSTOM_DOMAIN" --region "$OSS_REGION" 2>&1 | tail -2 || \
    echo "  (domain binding failed — likely missing ICP filing for a mainland bucket)" >&2
fi

echo "Uploading build/site → oss://$OSS_BUCKET/ …"
aliyun oss cp build/site/ "oss://$OSS_BUCKET/" --region "$OSS_REGION" --recursive --update \
  --acl public-read >/dev/null

echo "Deployed: $SITE_URL"
