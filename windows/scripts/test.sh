#!/bin/bash
# Unit tests for the Windows engines; runs on the Mac and in CI (no network, no Windows needed).
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/dotnet.sh build tests/Cicada.Tests -o build/tests -v quiet -nologo 2>&1 | grep -E ' error |warning CS' | sort -u || true
DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}" build/tests/Cicada.Tests
