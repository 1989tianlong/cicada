# Changelog

One section per release, newest first. `scripts/release.sh` needs the section, dated today;
the release workflow publishes it as the release notes.

## Unreleased

- Fixed: installing the virtual microphone looked like it failed ("系统还没识别到"). The package installed fine, but macOS only loads a new audio driver after its audio service restarts; the same password prompt now restarts it. If the driver is already there but not loaded, the app offers "让系统认出它" instead of reinstalling.
- New: a sound test for the virtual microphone: the app plays a sentence into it, listens back and shows what the room will hear.
- New: a settings window with a sidebar (听 / 我说话也翻译 / 字幕条 / 会议记录) replaces the settings sheet; the virtual microphone is set up from a three-step checklist there and in the first-run guide.

## 2.0.0 — 2026-11-01

- New: spoken-language auto-detection across the installed on-device models; translation target follows the system language or a manual choice.
- New: menu bar panel, meeting records with Markdown / Word / SRT export, and a three-step first-run guide with a built-in sample video.
- New: hold ⌥ Space to speak; your words are translated and spoken into a virtual microphone, installed from the app.
- New: the subtitle bar shows up only while someone talks, tucks away into a dot, turns see-through when the pointer passes; ⌃⌥S shows or hides it.
- Improved: on-device recognition with macOS 26 SpeechAnalyzer (no audio leaves the Mac), new icon, DMG installer.
- Improved: the subtitle bar is only as tall as the translation needs.
- Fixed: after a language switch the start of the sentence was sometimes lost.
- Fixed: when translation fails, your untranslated words are no longer spoken into the room.
