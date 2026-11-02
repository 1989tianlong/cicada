#!/usr/bin/env python3
"""UI strings: Chinese source text is the key, Resources/en.lproj/Localizable.strings has the English.

    python3 scripts/strings.py          # check: every key in the code has an English entry
    python3 scripts/strings.py --write  # also add missing keys (value = TODO) and rewrite zh-Hans

Keys come from the compiler (-emit-localized-strings), so interpolations are exactly the format
keys the app looks up ("已听到 %lld 句"). zh-Hans/Localizable.strings maps every key to itself:
the development region is English, so without it Chinese systems would fall back to English.
English plurals live in en.lproj/Localizable.stringsdict.
"""
import glob, json, os, re, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EN = os.path.join(ROOT, "Resources/en.lproj/Localizable.strings")
ZH = os.path.join(ROOT, "Resources/zh-Hans.lproj/Localizable.strings")
DICT = os.path.join(ROOT, "Resources/en.lproj/Localizable.stringsdict")
CJK = re.compile(r"[\u4e00-\u9fff]")


def code_keys():
    out = tempfile.mkdtemp()
    subprocess.run(["swift", "build", "--product", "LiveSubs", "-Xswiftc", "-emit-localized-strings",
                    "-Xswiftc", "-emit-localized-strings-path", "-Xswiftc", out],
                   cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
    keys = {}
    for f in sorted(glob.glob(os.path.join(out, "*.stringsdata"))):
        for entries in json.load(open(f))["tables"].values():
            for e in entries:
                if CJK.search(e["key"]):  # "%@ · %@" and the like need no translation
                    keys.setdefault(e["key"], os.path.basename(f).split(".")[0])
    return keys


def load(path):
    if not os.path.exists(path):
        return {}
    return json.loads(subprocess.check_output(["plutil", "-convert", "json", "-o", "-", path]))


def esc(s):
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def write(path, pairs):
    lines, last = [], None
    for k, v, group in pairs:
        if group != last:
            lines.append(f"\n/* {group} */")
            last = group
        lines.append(f'"{esc(k)}" = "{esc(v)}";')
    open(path, "w").write("\n".join(lines).lstrip() + "\n")


def main():
    keys = code_keys()
    en = load(EN)
    plurals = load(DICT)
    missing = [k for k in keys if k not in en]
    unused = [k for k in en if k not in keys]
    todo = [k for k, v in en.items() if v == "TODO"]
    for k in missing: print(f"missing  {keys[k]}: {k}")
    for k in unused: print(f"unused   {k}")
    for k in todo: print(f"todo     {k}")
    for k in plurals:
        if k not in keys: print(f"unused plural  {k}")
    if "--write" in sys.argv:
        write(EN, [(k, en.get(k, "TODO"), g) for k, g in keys.items()])
        write(ZH, [(k, k, g) for k, g in keys.items()])
    for p in (EN, ZH, DICT):
        if os.path.exists(p):
            subprocess.run(["plutil", "-lint", "-s", p], check=True)
    print(f"{len(keys)} keys, {len(missing)} missing, {len(unused)} unused, {len(todo)} TODO")
    sys.exit(1 if (missing or todo) and "--write" not in sys.argv else 0)


main()
