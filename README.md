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
<p align="center"><a href="docs/demo.mp4">▶ Watch the 52-second film with sound</a></p>

Cicada (知了, formerly Live Subs) is a macOS menu bar app that listens to what your Mac is playing. During a call, a livestream, a video or a voice room, it writes structured meeting notes on the left while a line-by-line bilingual transcript scrolls on the right. No bot joins the call, and the other side installs nothing. You can also switch to a minimal subtitle bar, or hold a key to speak and have the room hear you in their language.

## Features

### Live notes and bilingual transcript

- **Writes notes while the meeting runs.** A floating window updates roughly every 45 seconds with a summary, up to 8 topics with timestamped key points, a fishbone diagram when people discuss causes, conclusions and to-dos, and a glossary of names and terms. When the meeting ends, Cicada writes a complete final version. Notes are written in your language (Chinese when it is among your system languages) or, if you prefer, the meeting's own; the live and final versions always match.
- **Every conclusion links back to what was said.** Each conclusion or to-do shows how many lines of the transcript support it. Click to jump straight to that line.
- **Line-by-line bilingual transcript.** Each sentence appears in the original language with its translation right below, including the sentence still being spoken. Scroll up to read earlier lines without being pulled back; new lines queue up behind a `↓ N new lines` button.
- **Finds misrecognized names.** Cicada unifies names and terms across the notes and remembers misrecognized spellings. Pressing `⌘F` searches both the canonical spelling and the variants.
- **Adapts to your screen.** Widen the window past 760 pt to read notes and transcript side by side. Shrink it to a small card and it tells you what was added while collapsed. It stays out of screenshots and screen sharing, and clicking it does not steal focus from your meeting app.

### Live subtitles and language detection

- **Detects the language within half a second.** Every installed on-device speech model listens to the same audio at once, and the most confident one wins. Speech recognition runs on your Mac via Apple SpeechAnalyzer.
- **Translates into your language.** Follows your system languages by default (if the speaker is already using your primary language, Cicada translates into your next system language), or lets you pick a target language manually. Settings › Language shows the whole route in one line and lets subtitles show both lines, only the translation, or only the original (nothing is translated). A language chip in the notes window (`EN → 中`, or `EN → ZH` in the English UI) changes the languages for one meeting.
- **A subtitle bar that stays out of the way.** Press `⌃⌥S` to cycle between the notes window, the classic subtitle bar, and hidden. The bar appears only when someone speaks, shrinks to a dot when it is quiet, and turns see-through under your pointer so you can click right through it. Rest the pointer on it for 0.6 seconds to drag or resize, or double-click to reset. Each display remembers its own position and size.

### Speak back in their language

- **Push-to-talk interpreting.** Hold the right `⌥` key (or a shortcut you choose) and speak. The room hears your words translated through BlackHole 2ch, a virtual microphone you can install and test from inside the app with one click.
- **Natural voices or your own voice.** With a Ling API key, the Ming audio model listens and translates in one step in about 2 seconds, keeping names accurate. The other side can hear natural Ming voices (Emma, George, Charlotte for English; 小雅, 小棠, 小锋, 卓然 for Chinese; plus Japanese, Korean, German, French and Spanish), macOS system voices, or a clone of your own voice from an 8 to 30 second sample. Without a key, Cicada uses macOS system voices.

### Meeting records

- **Saved on your Mac.** Every session gets its own folder with the bilingual transcript, notes and audio recording. Speakers are labeled as you and the other side (individual remote speakers are not separated yet).
- **Export anywhere.** Export to Markdown or Word (both start with the meeting notes) or SRT subtitles. If you recorded a meeting without live notes, click **Generate Notes** afterward to generate them.

<p align="center">
  <img src="docs/panel.png" width="300" alt="The menu bar panel">
  &nbsp;
  <img src="docs/meetings.png" width="520" alt="A meeting record with each line in the original language and in translation">
</p>

## Cost & Privacy

Audio capture, language detection, speech recognition (Apple SpeechAnalyzer) and meeting recordings all stay on your Mac. The only data that leaves your device is the recognized text sent for translation and meeting notes, plus the short audio clips you speak while holding the talk key when using a Ling API key.

Subtitles, translation, meeting records and push-to-talk interpreting work out of the box without any API key (translation uses Google and falls back to Apple on-device translation).

Live meeting notes, higher-accuracy translation, one-step voice translation and voice cloning use your own Ling API key (Ant Group's model service at `ant-ling.com`, see [below](#ling-api-key)). The key is saved on your Mac in a file only your user account can read and is excluded from backups. Notes only send recognized text, and an hour of live meeting notes costs roughly ¥0.15 to ¥1 at current Ling pricing.

## Models

Without a Ling key, everything runs on Apple's on-device models plus Google Translate. With a key, Ling and Ming models take over the parts below, and the app falls back down the chain on any failure.

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
4. Optionally pick the model (`Ling-3.1-flash` by default) on the same page, and the Ming voice for each language under **Settings › Interpreting**.

To remove the key, click **Remove** on the same page.

## Requirements & Installation

Requires **macOS 26 or later** on **Apple silicon**.

1. Download **`Cicada-<version>-macOS-AppleSilicon.dmg`** from [Releases](https://github.com/wquguru/cicada/releases/latest) (or visit [cicada.indaloop.app](https://cicada.indaloop.app)). A `.zip` archive and `checksums.txt` (SHA-256) are published alongside the DMG.
2. Open the DMG and drag **Cicada** into **Applications**.
3. Because the app is ad-hoc signed and not notarized, macOS will block the first launch. Open **System Settings › Privacy & Security** and click **Open Anyway**.

On first launch, a three-step guide helps you grant system audio capture permission (and optionally microphone access), play a built-in sample video to see live subtitles right away, and optionally install the BlackHole 2ch virtual microphone with one click (requires your Mac administrator password once) with an automatic sound check.

## Usage

The app is in English or Chinese, following your macOS language (Settings › General › Language & Region, or per app).

1. Play any video, livestream or call. The live notes window opens by default, and pressing `⌃⌥S` switches between the notes window, the subtitle bar and hidden.
2. Click the Cicada icon in the menu bar to change the spoken language (auto by default), the target translation language, or the display mode.
3. To use live notes, paste your [Ling API key](https://chat.ant-ling.com/platform/api) in **Settings › AI Service** or in the notes window prompt.
4. To speak back in another language, turn on **Interpreting** in the menu bar panel, set your meeting app's microphone to **BlackHole 2ch**, and hold the right `⌥` key while speaking (macOS will ask for Input Monitoring permission the first time).
5. Open **会议记录** from the menu bar panel to search past transcripts (`⌘F`), generate notes for older sessions, or export to Markdown, Word or SRT.

## Uninstall

Quit Cicada and drag it from **Applications** to the Trash.

To remove all saved transcripts, notes and audio recordings, delete `~/Library/Application Support/LiveSubs`. To clear preferences, run:

```bash
defaults delete com.wquguru.cicada
```

## Development

Building from source requires Xcode Command Line Tools (`xcode-select --install`). Cicada has zero third-party dependencies and builds purely against macOS system frameworks.

```bash
scripts/build.sh            # dev build → build/Cicada.app ("Cicada Dev", runs beside the installed app)
open build/Cicada.app
scripts/package.sh          # release DMG + zip + checksums
```

See [AGENTS.md](AGENTS.md) for architecture details, dev vs. release builds, packaging and release workflows. The website source lives in `site/` and is generated by `scripts/site.py`. Release history is in [CHANGELOG.md](CHANGELOG.md) and on the website at [cicada.indaloop.app/changelog](https://cicada.indaloop.app/changelog/).

## License

[Apache-2.0](LICENSE). The BlackHole 2ch virtual audio driver is licensed under the GPL; Cicada does not bundle it and downloads the official release on demand when you choose to install it.
