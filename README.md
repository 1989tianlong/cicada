<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="Cicada icon">
</p>

<h1 align="center">Cicada · 知了</h1>

<p align="center">
  Every call. Every stream. No language barrier.<br>
  Live meeting notes, bilingual transcripts, subtitles and interpreting for anything your Mac plays.
</p>

<p align="center">
  <a href="https://cicada.indaloop.app"><img src="https://img.shields.io/badge/Website-cicada.indaloop.app-E8552B?style=for-the-badge" alt="Website: cicada.indaloop.app" height="36"></a>
  &nbsp;
  <a href="https://github.com/wquguru/cicada/releases/latest"><img src="https://img.shields.io/badge/Download-macOS-15171C?style=for-the-badge&logo=apple&logoColor=white" alt="Download for macOS" height="36"></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-26%2B-black" alt="macOS 26+">
  <img src="https://img.shields.io/badge/Apple%20silicon-only-black" alt="Apple silicon">
  <img src="https://img.shields.io/badge/Swift-5-orange" alt="Swift 5">
  <img src="https://img.shields.io/badge/license-Apache--2.0-blue" alt="Apache-2.0">
</p>

<p align="center"><a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a></p>

<p align="center">
  <a href="docs/demo.mp4"><img src="docs/demo.gif" width="800" alt="An English meeting plays while Cicada writes Chinese notes on the left and a bilingual transcript on the right"></a>
</p>
<p align="center"><a href="docs/demo.mp4">▶ Watch the 52-second demo with sound</a></p>

Cicada (知了, formerly Live Subs) is a macOS menu bar app that listens to what your Mac is playing. During a call, livestream, video or voice room, it writes structured meeting notes on the left while a line-by-line bilingual transcript scrolls on the right. No bot joins the call, and the other side installs nothing. You can also switch to a compact subtitle bar, or hold a key to speak and have the room hear you in their language.

## Features

### Live notes and bilingual transcript

- **Writes notes while the meeting runs.** A floating window updates roughly every 45 seconds with a summary, up to 8 topics with timestamped key points, conclusions, to-dos, a fishbone diagram when discussing causes, and a glossary of names and terms, then generates a complete final version when the meeting ends. Notes default to your language (or the meeting's own), and every conclusion or to-do clicks straight back to the supporting lines in the transcript.
- **Line-by-line bilingual transcript and name search.** Each sentence appears in the original language with its translation right below. Cicada unifies names and terms across the notes and remembers misrecognized spellings, so `⌘F` searches both the canonical spelling and the variants.

### Live subtitles and language detection

- **On-device language detection.** After someone speaks for about 3 seconds, every installed on-device speech model listens to the same 3 to 6 second audio window at once, and the most confident one wins. Speech recognition runs locally via Apple SpeechAnalyzer.
- **Translates into your language with a compact subtitle bar.** Follows your system languages by default, and subtitles can show both languages, translation only, or original only. Press `⌃⌥S` to cycle between the notes window, the subtitle bar, and hidden; the bar appears only when someone speaks and turns see-through under your pointer so you can click right through it.

### Speak back in their language

- **Push-to-talk interpreting.** Hold the right `⌥` key (or a custom shortcut) and speak. The room hears your translated voice through BlackHole 2ch, a virtual microphone you can install and test from inside the app with one click.
- **Ming voices and voice cloning.** With a Ling API key, the Ming audio model listens and translates in one step in about 2 seconds. The other side can hear natural Ming voices (English, Chinese, Japanese, Korean, German, French, Spanish), macOS system voices, or a clone of your own voice from an 8 to 30 second sample; without a key, Cicada uses macOS system voices.

### Meeting records

- **Saved on your Mac.** Every session gets its own folder with the bilingual transcript, notes and audio recording. Speakers are labeled as you and the other side; "you" covers only what you say while holding the talk key, not what you say into the meeting directly, and individual remote speakers are not separated yet (see [roadmap](#roadmap)).
- **Export anywhere.** Export to Markdown, Word (both start with the meeting notes) or SRT subtitles. If you recorded a meeting without live notes, click **Generate Notes** afterward to create them.

<p align="center">
  <img src="docs/panel.png" width="300" alt="The menu bar panel">
  &nbsp;
  <img src="docs/meetings.png" width="520" alt="A meeting record with each line in the original language and in translation">
</p>

## Privacy & Permissions

Audio capture, language detection, speech recognition (Apple SpeechAnalyzer) and meeting recordings all stay on your Mac. The only data that leaves your device is the recognized text sent for translation and meeting notes, plus the short audio clips you speak while holding the talk key when using a Ling API key. Without an API key, subtitles, translation (via Google with Apple on-device fallback), meeting records and push-to-talk interpreting all work. Live meeting notes, one-step voice translation and voice cloning use your own Ling API key (Ant Group's model service, see [below](#ling-api-key)), and an hour of live notes costs roughly ¥0.15 to ¥1 at current Ling pricing; Ling gives ¥10 of credit every month, about 10–50 hours of meetings.

Cicada asks for a permission only when you use the feature that needs it; everything else keeps working if you decline.

| Permission | What it's for | When it's asked | Without it |
|---|---|---|---|
| System audio recording (Screen & System Audio Recording) | Hearing what your Mac plays, for subtitles. Never records the screen or its own sound | Onboarding step 1, or the first time it listens | No subtitles or notes |
| Microphone | Recording only while you hold the talk key, for speak-back | When you turn on speak-back | No speak-back |
| Input Monitoring | Only to tell whether the right `⌥` was pressed on its own (listen-only; nothing is blocked or logged) | The first time you talk with right `⌥` | Pick a `⌃`/`⌘` combination in Settings instead; it needs no permission |
| Administrator password | Installing the BlackHole 2ch virtual microphone and restarting the system audio service | When you click Install in onboarding or Settings, once | The room can't hear your translation; everything else works |

- **Network and virtual microphone**: Cicada only connects to Google Translate (`translate.googleapis.com`), Ling / Ming when a key is configured (`api.ant-ling.com`), the official BlackHole download, and GitHub once a day for update checks. BlackHole is downloaded from the official Apple-notarized package and verified against a hardcoded SHA-256 checksum before installing.
- **No analytics or servers of our own**: There is no analytics, no tracking, and no backend server. Diagnostics only log timings and counts locally in the meeting folder.
- **Local storage**: Meetings, recordings and notes live in `~/Library/Application Support/LiveSubs`. Your Ling key and voice sample are readable only by your user account, excluded from Time Machine backups, and never written to logs or exports.
- **Private notes window**: Hidden from screen sharing, screen recording and screenshots.

## Models

Without a Ling key, everything runs on Apple's on-device models plus Google Translate; with a key, Ling and Ming models handle the tasks below and fall back automatically if a request fails.

| Feature | With a Ling key | Without a key / fallback |
|---|---|---|
| Speech recognition and language detection | Apple `SpeechAnalyzer` / `SpeechTranscriber` (on device) | same |
| Translating finished sentences | Ling `Ling-3.1-flash` (or `Ling-3.0-flash`, set in Settings › AI Service) | Google Translate → Apple `Translation` (on device) |
| Translating the sentence still being spoken | Google Translate (saves Ling's rate limit) | Apple `Translation` (on device) |
| Live notes and the final version | Ling `Ling-3.1-flash` (same setting) | not available |
| Checking the key | Ling `Ling-3.0-tiny` (one token) | — |
| Interpreting: hearing and translating what you say | Ming `Ming-3.0-audio-flash`, one step | Apple on-device transcript, then the translation chain above |
| Interpreting: the voice the room hears, voice cloning | Ming `Ming-3.0-tts-0.5B` | macOS system voices (`AVSpeechSynthesizer`); no cloning |

<a id="ling-api-key"></a>
## Setting up a Ling API key

1. Sign up or log in on the [Ling open platform](https://chat.ant-ling.com/platform/api).
2. Click **创建令牌** (create token) and copy the key that starts with `sk-`.
3. In Cicada, open **Settings › AI Service**, paste the key and click **Save and check** (or paste it in the prompt at the top of the notes window). A one-token request confirms it works.
4. Optionally pick the model (`Ling-3.1-flash` by default) on the same page, and the Ming voice for each language under **Settings › Interpreting**. To remove the key, click **Remove** on the same page.

## Requirements & Installation

Requires **macOS 26 or later** on **Apple silicon**.

Download `Cicada-<version>-macOS-AppleSilicon.dmg` from [Releases](https://github.com/wquguru/cicada/releases/latest) or [the website](https://cicada.indaloop.app), open it and drag **Cicada** into **Applications**. Builds are ad-hoc signed and not notarized yet (see [roadmap](#roadmap)), so if macOS blocks the first launch, open **System Settings › Privacy & Security** and click **Open Anyway**. Each release includes `checksums.txt`; verify with `shasum -a 256 Cicada-*.dmg`.

The first-launch guide walks you through permissions, your Ling key (or skip it for now), a sample video and, if you want, the virtual microphone. Later updates show as an orange dot on the menu bar icon; one click installs them and keeps your permissions.

## Usage

The UI is available in English, Chinese, Japanese and Korean, following your macOS language (or set per app in **System Settings › General › Language & Region**).

1. Play any video, livestream or call. The live notes window opens by default, and pressing `⌃⌥S` switches between the notes window, the subtitle bar and hidden.
2. Click the Cicada icon in the menu bar to change the spoken language (auto by default), the target translation language, or the display mode.
3. To use live notes, paste your [Ling API key](https://chat.ant-ling.com/platform/api) in **Settings › AI Service** or in the notes window prompt.
4. To speak back in another language, turn on **Interpreting** in the menu bar panel, set your meeting app's microphone to **BlackHole 2ch**, and hold the right `⌥` key while speaking.
5. Open **会议记录** from the menu bar panel to search past transcripts (`⌘F`), generate notes for older sessions, or export to Markdown, Word or SRT.

## Roadmap

In rough order; tell us what you need in Issues.

- **Recording what you say**, listening to your microphone during meetings with echo cancellation so your own proposals and to-dos are included in the transcript and notes.
- **Older macOS support (targeting macOS 14.4+)**, falling back to earlier system speech recognition and translation APIs on older versions.
- **Developer ID signing and notarization**, removing the "Open Anyway" prompt on first launch and storing the AI key in the macOS Keychain.
- **Telling speakers apart**, separating and renaming individual remote speakers and tagging conclusions and to-dos with who said them.
- **Local notes without an API key** using Apple's on-device model on supported Macs, plus **custom AI providers** for any OpenAI-compatible endpoint.
- **Speaker recognition**, remembering frequent meeting participants by voice on your Mac so you don't have to rename them each call.
- **Windows and Android**, sharing the same notes and meeting-record formats (iPhone / iPad are not planned due to iOS audio capture restrictions).

See [docs/ROADMAP.md](docs/ROADMAP.md) for details and trade-offs on each item.

## Uninstall

Quit Cicada and drag it from **Applications** to the Trash. To remove all saved transcripts, notes and audio recordings, delete `~/Library/Application Support/LiveSubs`. To clear preferences, run:

```bash
defaults delete com.wquguru.cicada
```

## Development

Building from source requires Xcode Command Line Tools (`xcode-select --install`). Cicada has no third-party dependencies and builds directly against macOS system frameworks.

```bash
scripts/build.sh            # dev build → build/Cicada.app ("Cicada Dev", runs beside the installed app)
open build/Cicada.app
scripts/package.sh          # release DMG + zip + checksums
```

See [AGENTS.md](AGENTS.md) for architecture details and release workflows. The website source lives in `site/` and is generated by `scripts/site.py`. Release history is in [CHANGELOG.md](CHANGELOG.md) and on the website at [cicada.indaloop.app/changelog](https://cicada.indaloop.app/changelog/).

## License

[Apache-2.0](LICENSE). The BlackHole 2ch virtual audio driver is licensed under the GPL; Cicada does not bundle it and downloads the official release on demand when you choose to install it.
