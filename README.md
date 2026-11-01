<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="Live Subs icon">
</p>

<h1 align="center">Live Subs</h1>

<p align="center">
  Live translated subtitles for anything your Mac plays — and your own voice, translated back into the call.
</p>

<p align="center">
  <a href="https://github.com/wquguru/live-subs/releases/latest"><b>Download for macOS</b></a> · <a href="CHANGELOG.md"><b>What’s new</b></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-26%2B-black" alt="macOS 26+">
  <img src="https://img.shields.io/badge/Apple%20silicon-only-black" alt="Apple silicon">
  <img src="https://img.shields.io/badge/Swift-5-orange" alt="Swift 5">
</p>

<p align="center">
  <img src="docs/hero.jpg" width="880" alt="A livestream in English with Live Subs showing the Chinese translation in a subtitle bar">
</p>

<p align="center"><a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a></p>

---

Live Subs listens to what your Mac is playing — a livestream, a video, a meeting, a voice room — works out which language is being spoken, and shows the translation in a small subtitle bar on top of everything. Recognition happens on your Mac; only the recognised text is sent for translation.

## Features

- **Detects the language for you** — every installed on-device speech model listens to the same few seconds; the most confident one wins, usually within half a second.
- **Translates into your language** — follows your system languages by default (English audio on an English Mac goes to your next language), or pick one.
- **Stays out of the way** — the subtitle bar appears only while someone talks, tucks into a small dot when it's quiet, and turns see-through when your pointer passes over it, so you can still click what's underneath. Rest the pointer on it to drag or resize; ⌃⌥S hides it.
- **Speak back** — hold the right ⌥ key and talk; the room hears your words translated, through a virtual microphone you install from the app.
- **Meeting records** — every session is saved as a bilingual transcript (with the audio, on your Mac only) and exports to Markdown, Word or SRT.
- **Private by design** — audio capture, language detection and speech recognition all run on-device.

<p align="center">
  <img src="docs/panel.png" width="300" alt="The menu bar panel">
  &nbsp;
  <img src="docs/meetings.png" width="520" alt="A meeting record with each line in the original language and in translation">
</p>

<p align="center">
  <img src="docs/onboarding.png" width="520" alt="First-run guide playing the built-in sample with live subtitles">
</p>

## Requirements

- macOS 26 on Apple silicon
- Building from source: Xcode Command Line Tools (`xcode-select --install`)

## Installation

Download **`LiveSubs-<version>-macOS-AppleSilicon.dmg`** from [Releases](https://github.com/wquguru/live-subs/releases), open it and drag **Live Subs** into **Applications**. A `.zip` of the app and `checksums.txt` (SHA-256) sit next to it.

The app is ad-hoc signed (not notarized). On first launch macOS blocks it: open **System Settings › Privacy & Security** and click **Open Anyway**.

The first launch walks you through three steps: turn on **system audio recording** (and, optionally, the microphone), play the built-in sample to see subtitles appear, and — if you want to speak back — install the virtual microphone with one click (it asks for your password once); a quick sound test then confirms the room will hear you.

## Usage

1. Play anything with sound. Subtitles appear at the bottom of the screen.
2. Click the menu bar icon to change the heard language (auto by default), the language to translate into, or how the subtitle bar behaves.
3. To speak back: turn on **我说话也翻译**, choose **BlackHole 2ch** as the microphone in your meeting app, then hold the right ⌥ key while you talk (allow "Input Monitoring" when asked). Both shortcuts can be changed in settings.
4. **会议记录** in the panel opens your transcripts: search, switch between bilingual / original / translation, export.

### Uninstall

Quit Live Subs and move it to the Trash. Transcripts and recordings stay in `~/Library/Application Support/LiveSubs` until you delete them; settings are in `defaults delete com.wquguru.cicada`.

## Development

```bash
scripts/build.sh            # dev build → build/LiveSubs.app ("Live Subs Dev", runs beside the installed app)
open build/LiveSubs.app
scripts/package.sh          # release DMG + zip + checksums
```

See [AGENTS.md](AGENTS.md) for the architecture, dev vs release builds, packaging, testing and releases.
