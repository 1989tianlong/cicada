#!/bin/bash
# Builds the Windows app on the Mac: build/Cicada-win-x64/ and build/Cicada-win-arm64/, each a
# self-contained Cicada.exe plus Resources/. RELEASE=1 for a release build (else a dev build,
# which keeps its records under "Cicada Dev" and opens the debug pipe).
set -euo pipefail
cd "$(dirname "$0")/.."
root=..
mkdir -p build/icon src/Cicada/Assets

# The icon (committed, regenerated here): the Mac app's 256 px icon at the sizes Windows asks for, PNGs inside one .ico.
for s in 16 24 32 48 64 256; do sips -z $s $s "$root/docs/icon.png" --out "build/icon/$s.png" >/dev/null; done
python3 - build/icon <<'PY'
import struct, sys, os
d = sys.argv[1]; sizes = [16, 24, 32, 48, 64, 256]
pngs = [open(os.path.join(d, f"{s}.png"), "rb").read() for s in sizes]
out = struct.pack("<HHH", 0, 1, len(sizes)); offset = 6 + 16 * len(sizes)
for s, p in zip(sizes, pngs):
    out += struct.pack("<BBBBHHII", s % 256, s % 256, 0, 0, 1, 32, len(p), offset); offset += len(p)
open(os.path.join(d, "..", "..", "src", "Cicada", "Assets", "cicada.ico"), "wb").write(out + b"".join(pngs))
PY

# The onboarding sample as 16 kHz WAV: SoundPlayer and the file source both read WAV only.
afconvert -f WAVE -d LEI16@16000 -c 1 "$root/Resources/sample/sample.m4a" src/Cicada/Assets/sample.wav

config=Debug; [ "${RELEASE:-}" = 1 ] && config=Release
for rid in win-x64 win-arm64; do
  out="build/Cicada-$rid"
  rm -rf "$out"
  scripts/dotnet.sh publish src/Cicada -c "$config" -r "$rid" -o "$out" -p:DebugType=embedded -v quiet -nologo 2>&1 | grep -E ' error |warning CS' | sort -u || true
  [ -f "$out/Cicada.exe" ] || { echo "build failed for $rid" >&2; exit 1; }
  [ "$config" = Debug ] && printf '@echo off\r\nstart "" "%%~dp0Cicada.exe" --dev\r\n' > "$out/Cicada Dev.cmd"
  echo "$out/Cicada.exe ($(du -h "$out/Cicada.exe" | cut -f1))"
done
