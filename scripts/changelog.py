#!/usr/bin/env python3
"""Writes a version's CHANGELOG.md section from the commits since the last tag.

scripts/changelog.py 1.0.1            # replaces "## Unreleased" (or adds a section) dated today
scripts/changelog.py 1.0.1 --print    # only prints the section

Release notes are the commit subjects: feat: goes under New, fix: under Fixed, and a (site) scope
under Website; chore/docs/build/test/refactor stay out. Each line links its commit. Lines written by
hand under "## Unreleased" stay on top, as the release's one-line summary.
"""
import datetime
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = "https://github.com/wquguru/cicada"
SUBJECT = re.compile(r"^(feat|fix|perf)(?:\(([^)]*)\))?!?: (.+)$")


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def commits():
    try:
        since = git("describe", "--tags", "--abbrev=0") + "..HEAD"
    except subprocess.CalledProcessError:
        since = "HEAD"  # no tag yet: everything
    out = git("log", "--reverse", "--format=%H%x09%s", since)
    return [line.split("\t", 1) for line in out.splitlines() if line]


def section(version, summary):
    groups = {"New": [], "Fixed": [], "Website": []}
    for sha, subject in commits():
        m = SUBJECT.match(subject)
        if not m:
            continue
        kind, scope, text = m.groups()
        group = "Website" if scope == "site" else ("New" if kind == "feat" else "Fixed")
        groups[group].append(f"- {text[0].upper() + text[1:]} ([{sha[:7]}]({REPO}/commit/{sha}))")
    lines = [f"## {version} — {datetime.date.today().isoformat()}", ""]
    if summary:
        lines += [summary, ""]
    for name, items in groups.items():
        if items:
            lines += [f"### {name}", "", *items, ""]
    return "\n".join(lines)


def main():
    if len(sys.argv) < 2 or not re.fullmatch(r"\d+\.\d+\.\d+", sys.argv[1]):
        sys.exit("usage: scripts/changelog.py <x.y.z> [--print]")
    version = sys.argv[1]
    path = os.path.join(ROOT, "CHANGELOG.md")
    text = open(path, encoding="utf-8").read()
    # The "## Unreleased" block, if any: its text becomes the summary.
    m = re.search(r"^## Unreleased\n(.*?)(?=^## |\Z)", text, re.M | re.S)
    summary = m.group(1).strip() if m else ""
    new = section(version, summary)
    if "--print" in sys.argv:
        print(new)
        return
    if m:
        text = text[:m.start()] + new + "\n" + text[m.end():]
    else:
        first = re.search(r"^## ", text, re.M)
        at = first.start() if first else len(text)
        text = text[:at] + new + "\n" + text[at:]
    open(path, "w", encoding="utf-8").write(text)


if __name__ == "__main__":
    main()
