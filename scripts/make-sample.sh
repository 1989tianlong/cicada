#!/bin/bash
# Builds the onboarding sample: Resources/sample/sample.mp4 (muted video track for display)
# and Resources/sample/sample.m4a (the speech, played by a helper process so the app's
# own system-audio capture hears it — the app excludes its own process).
set -euo pipefail
cd "$(dirname "$0")/.."
T=$(mktemp -d)
say -v 'Eddy (English (US))' -r 175 -o "$T/speech.aiff" \
  "Hi everyone, welcome to the live stream. Today we're talking about real time translation on the Mac."
swift scripts/make-frame.swift "$T/frame.png"
DUR=$(afinfo "$T/speech.aiff" | awk '/estimated duration/{print $3}')
ffmpeg -y -loglevel error -i "$T/speech.aiff" -c:a aac -b:a 64k Resources/sample/sample.m4a
ffmpeg -y -loglevel error -loop 1 -framerate 25 -t "$DUR" -i "$T/frame.png" \
  -vf "zoompan=z='min(zoom+0.0006,1.06)':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=1:s=960x540:fps=25,format=yuv420p" \
  -c:v libx264 -preset slow -crf 30 -an -movflags +faststart Resources/sample/sample.mp4
rm -rf "$T"
ls -la Resources/sample/sample.*
