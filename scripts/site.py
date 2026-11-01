#!/usr/bin/env python3
"""Builds the website (GitHub Pages) from site/ into build/site/.

site/index.html and site/changelog.html are templates; header.html and footer.html are shared.
site/changelog.json is the Chinese changelog (newest first; "date": null = not released yet).
Also writes changelog/index.html, feed.xml (Atom), sitemap.xml and robots.txt.

    python3 scripts/site.py                 # → build/site
    python3 -m http.server -d build/site    # preview at http://localhost:8000/
SITE_URL overrides the public address (default: the repo's GitHub Pages address).
"""
import html
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime, timezone

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT_DIR, "site")
OUT = os.path.join(ROOT_DIR, "build", "site")
SITE = (os.environ.get("SITE_URL") or "https://wquguru.github.io/live-subs/").rstrip("/") + "/"
REPO = "https://github.com/wquguru/live-subs"
DOWNLOAD = REPO + "/releases/latest"
STATIC = ["style.css", "icon.svg", "icon.png", "og.png", "img"]
APPS = ["Zoom", "Microsoft Teams", "飞书", "腾讯会议", "Google Meet", "X Spaces", "YouTube 直播",
        "Twitch", "Discord", "B 站直播", "钉钉", "播客"]
KINDS = [("new", "新功能"), ("improved", "改进"), ("fixed", "修复")]

e = html.escape


def read(name):
    with open(os.path.join(SRC, name), encoding="utf-8") as f:
        return f.read()


def write(rel, text):
    path = os.path.join(OUT, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def fill(text, values):
    for k, v in values.items():
        text = text.replace("{{" + k + "}}", v)
    if "{{" in text:
        sys.exit("site.py: unfilled placeholder near: " + text[text.index("{{"):][:40])
    return text


def zh_date(d):
    y, m, day = d.split("-")
    return f"{int(y)} 年 {int(m)} 月 {int(day)} 日"


def anchor(version):
    return "v" + version.replace(".", "-")


def rev():
    try:
        return subprocess.check_output(["git", "rev-parse", "--short=12", "HEAD"], cwd=ROOT_DIR, text=True).strip()
    except Exception:
        return "dev"


def release_html(r, latest_released):
    date = (f'<time datetime="{r["date"]}">{zh_date(r["date"])}</time>' if r["date"]
            else '<span>即将发布</span>')
    badge = '<span class="new">最新</span>' if r["version"] == latest_released else ""
    img = ""
    if r.get("image"):
        img = f'<img src="../{e(r["image"]["src"])}" alt="{e(r["image"]["alt"])}" loading="lazy">'
    groups = []
    for kind, name in KINDS:
        items = [i for i in r["items"] if i["kind"] == kind]
        if items:
            lis = "".join(f'<li><strong>{e(i["title"])}</strong>{e(i["text"])}</li>' for i in items)
            groups.append(f'<div class="group" data-kind="{kind}"><h3><i></i>{name}</h3><ul>{lis}</ul></div>')
    a = anchor(r["version"])
    dl = (f'<a class="btn btn-dark desk" href="{REPO}/releases/tag/v{r["version"]}">下载 {r["version"]}</a>'
          if r["date"] else "")
    return (f'<article class="card release rv" id="{a}">'
            f'<div class="line"><span class="ver">{r["version"]}</span>{date}{badge}'
            f'<a class="perma" href="#{a}" aria-label="{r["version"]} 的永久链接">#</a></div>'
            f'<h2>{r["version"]}：{e(r["title"])}</h2><p>{e(r["summary"])}</p>{img}{"".join(groups)}'
            f'<div class="acts">{dl}<a class="btn btn-light" href="{REPO}/releases">在 GitHub 上看</a></div></article>')


def main():
    with open(os.path.join(SRC, "changelog.json"), encoding="utf-8") as f:
        log = json.load(f)
    released = [r for r in log if r["date"]]
    if not released:
        sys.exit("site.py: changelog.json has no released version")
    latest = released[0]
    common = {"SITE": SITE, "REPO": REPO, "DOWNLOAD": DOWNLOAD, "VERSION": latest["version"], "REV": rev()}

    if os.path.isdir(OUT):
        shutil.rmtree(OUT)
    os.makedirs(OUT)
    for name in STATIC:
        src = os.path.join(SRC, name)
        if os.path.isdir(src):
            shutil.copytree(src, os.path.join(OUT, name))
        elif os.path.exists(src):
            shutil.copy2(src, OUT)

    def page(template, root, cl_current, extra):
        v = dict(common, ROOT=root, CL_CURRENT=' aria-current="page"' if cl_current else "")
        v["HEADER"] = fill(read("header.html"), v)
        v["FOOTER"] = fill(read("footer.html"), v)
        v.update(extra)
        return fill(read(template), v)

    # Home
    apps = "".join(f"<li>{e(a)}</li>" for a in APPS)
    apps += "".join(f'<li aria-hidden="true">{e(a)}</li>' for a in APPS)  # second copy for the seamless loop
    cards = []
    for r in log[:2]:
        when = zh_date(r["date"]) if r["date"] else "即将发布"
        cards.append(f'<a class="card ucard rv" href="changelog/#{anchor(r["version"])}">'
                     f'<span class="when"><span class="ver">{r["version"]}</span>{when}</span>'
                     f'<strong>{e(r["title"])}</strong><span class="d">{e(r["summary"])}</span></a>')
    app_ld = {
        "@context": "https://schema.org", "@type": "SoftwareApplication",
        "name": "知了 Cicada", "alternateName": ["知了", "Cicada"],
        "description": "Mac 上的实时翻译字幕、同声传译和 AI 会议纪要，任意会议与直播都能用。",
        "applicationCategory": "BusinessApplication", "operatingSystem": "macOS 26",
        "softwareVersion": latest["version"], "url": SITE, "downloadUrl": DOWNLOAD,
        "image": SITE + "icon.png", "license": "https://www.apache.org/licenses/LICENSE-2.0",
        "isAccessibleForFree": True, "offers": {"@type": "Offer", "price": "0", "priceCurrency": "USD"},
        "releaseNotes": SITE + "changelog/", "codeRepository": REPO,
    }
    write("index.html", page("index.html", "", False, {
        "APPS": apps, "LATEST": "".join(cards),
        "JSONLD": json.dumps(app_ld, ensure_ascii=False).replace("</", "<\\/")}))

    # Changelog
    counts = {k: sum(1 for r in log for i in r["items"] if i["kind"] == k) for k, _ in KINDS}
    filters = f'<button type="button" data-kind="all" aria-pressed="true">全部<span>{sum(counts.values())}</span></button>'
    filters += "".join(f'<button type="button" data-kind="{k}" aria-pressed="false">{n}<span>{counts[k]}</span></button>'
                       for k, n in KINDS)
    versions = "".join(f'<a href="#{anchor(r["version"])}"><b>{r["version"]}</b>'
                       f'<span>{r["date"] or "即将发布"}</span></a>' for r in log)
    crumbs_ld = {"@context": "https://schema.org", "@type": "BreadcrumbList", "itemListElement": [
        {"@type": "ListItem", "position": 1, "name": "知了", "item": SITE},
        {"@type": "ListItem", "position": 2, "name": "更新日志", "item": SITE + "changelog/"}]}
    write("changelog/index.html", page("changelog.html", "../", True, {
        "LATEST_VERSION": latest["version"], "LATEST_TITLE": e(latest["title"]),
        "FILTERS": filters, "VERSIONS": versions,
        "RELEASES": "".join(release_html(r, latest["version"]) for r in log),
        "JSONLD": json.dumps(crumbs_ld, ensure_ascii=False)}))

    # Atom feed: released versions only
    entries = []
    for r in released:
        body = "".join(f"<li><strong>{e(i['title'])}</strong>{e(i['text'])}</li>" for i in r["items"])
        entries.append(
            f"<entry><title>{r['version']}：{e(r['title'])}</title>"
            f"<id>{SITE}changelog/#{anchor(r['version'])}</id>"
            f"<link href=\"{SITE}changelog/#{anchor(r['version'])}\"/>"
            f"<updated>{r['date']}T00:00:00Z</updated>"
            f"<summary>{e(r['summary'])}</summary>"
            f"<content type=\"html\">{e('<p>' + e(r['summary']) + '</p><ul>' + body + '</ul>')}</content></entry>")
    write("feed.xml", '<?xml version="1.0" encoding="utf-8"?>\n'
          '<feed xmlns="http://www.w3.org/2005/Atom" xml:lang="zh-CN">'
          f'<title>知了更新日志</title><id>{SITE}changelog/</id>'
          f'<link href="{SITE}changelog/"/><link rel="self" href="{SITE}feed.xml"/>'
          f'<updated>{latest["date"]}T00:00:00Z</updated><author><name>知了 Cicada</name></author>'
          + "".join(entries) + "</feed>\n")

    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    write("sitemap.xml", '<?xml version="1.0" encoding="utf-8"?>\n'
          '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'
          f"<url><loc>{SITE}</loc><lastmod>{today}</lastmod></url>"
          f"<url><loc>{SITE}changelog/</loc><lastmod>{today}</lastmod></url></urlset>\n")
    write("robots.txt", f"User-agent: *\nAllow: /\nSitemap: {SITE}sitemap.xml\n")
    print("site.py: wrote", os.path.relpath(OUT, ROOT_DIR), "for", SITE)


if __name__ == "__main__":
    main()
