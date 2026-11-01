# Changelog

One section per release, newest first. `scripts/release.sh` needs the section, dated today;
the release workflow publishes it as the release notes.

## Unreleased

- Fixed: installing the virtual microphone looked like it failed ("系统还没识别到"). The package installed fine, but macOS only loads a new audio driver after its audio service restarts; the same password prompt now restarts it. If the driver is already there but not loaded, the app offers "让系统认出它" instead of reinstalling.
- New: a sound test for the virtual microphone: the app plays a sentence into it, listens back and shows what the room will hear.
- New: a settings window with a sidebar (听 / 我说话也翻译 / 字幕条 / 会议记录) replaces the settings sheet; the virtual microphone is set up from a three-step checklist there and in the first-run guide.
- Changed: hold the right ⌥ key on its own to talk, instead of ⌥ Space (which other apps' launchers often use, and which types a space). Pressing another key while holding it cancels, so ⌥ + letter still types. It needs the "输入监控" permission; the app asks for it.
- New: speak-back can use Ming's voice through the Ling key (Settings › AI 服务 › 我说话时的声音), streamed as it is generated; without a key it uses the system voice.
- New: meeting records show the notes (纪要 / 文字记录); a meeting recorded without notes gets a "生成纪要" button. Markdown and Word exports start with the notes.
- New: a live notes window, now the default display while listening: notes, the transcript and a caption line in one floating window that can be moved and resized anywhere (a small card under 360 px with "我刚走神了，错过什么？", tabs in between, notes beside the transcript from 760 px), never shows up in screen sharing, and remembers its frame. The menu bar panel and settings choose 实时纪要 / 字幕条 / 不显示; ⌃⌥S now cycles through them.
- New: live meeting notes. With a key, Ling updates the notes about every 45 s while the meeting runs (summary, topics with key points, a fishbone diagram where causes are discussed, conclusions and to-dos with how many lines back them, names and terms with their misrecognised forms) and rewrites them once over the whole transcript when it ends. Notes are saved with the meeting.
- New: with a key, finished sentences and speak-back are translated by Ling (names kept consistent through the notes' glossary); if Ling is busy or fails, that sentence falls back to Google, then to Apple's on-device translation. Partial text while someone is still talking stays on Google.
- New: Settings › AI 服务 takes your own Ling (ant-ling.com) API key. It is kept in the macOS Keychain, checked with a one-token request, and shown masked; without a key everything works as before.
- New: both shortcuts (talk, hide/show the subtitle bar) can be changed in settings: click and press new keys. Combinations without ⌃ or ⌘, system shortcuts and ones another app already uses are refused with a reason.

## 2.0.0 — 2026-11-01

- New: spoken-language auto-detection across the installed on-device models; translation target follows the system language or a manual choice.
- New: menu bar panel, meeting records with Markdown / Word / SRT export, and a three-step first-run guide with a built-in sample video.
- New: hold ⌥ Space to speak; your words are translated and spoken into a virtual microphone, installed from the app.
- New: the subtitle bar shows up only while someone talks, tucks away into a dot, turns see-through when the pointer passes; ⌃⌥S shows or hides it.
- Improved: on-device recognition with macOS 26 SpeechAnalyzer (no audio leaves the Mac), new icon, DMG installer.
- Improved: the subtitle bar is only as tall as the translation needs.
- Fixed: after a language switch the start of the sentence was sometimes lost.
- Fixed: when translation fails, your untranslated words are no longer spoken into the room.
