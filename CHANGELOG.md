# Changelog

One section per release, newest first. `scripts/release.sh` needs the section, dated today;
the release workflow publishes it as the release notes.

## Unreleased

- Changed: Live Subs is now 知了 (Cicada in English): new name, new logo, new app id (`com.wquguru.cicada`). macOS treats it as a new app, so it asks again for system audio, microphone and Input Monitoring, and settings and the AI key start fresh; meeting records are kept. Delete the old Live Subs from Applications.
- New: choose the voice the room hears for each language (Settings › 同声传译 › 对方听到的声音): natural Ming voices, two women and two men where available (Emma, George, Charlotte in English; 小雅, 小棠, 小锋, 卓然 in Chinese; Japanese, Korean, German, French and Spanish too), the Mac's own voices, each with a play button. Or record 15 s of your own voice and the room hears you, in any language (with your accent, about 1.5 s later than the built-in voices). The recording stays on your Mac and is sent to Ling only with what you say.
- Changed: clearer wording throughout the Chinese interface.
- New: the project is licensed under Apache-2.0, and has a website (Chinese first) with a searchable changelog and an RSS feed.
- Changed: the Ling API key is kept in a file only your account can read (in the app's Application Support folder, left out of backups) instead of the Keychain, which asked for your password every time the app was updated. A key saved earlier is moved over once (one last password prompt).
- Changed: settings are now 显示 (who is heard and what it's translated into, then how it shows) / 同声传译 (was 我说话也翻译; the panel uses the new name too) / 会议记录 / AI 服务.
- New: a 诊断 switch at the bottom left of settings. On, it adds a 诊断 tab: how long each sentence took from the last words to the translation, which translator answered (Ling, Google or on-device) and why one was skipped (search hijack, rate limit, timeout), Ling's request rate and token use, and a "复制诊断信息" button. Only timings and counts are kept (`metrics.jsonl` in the meeting folder), never what was said.

- Changed: the transcript stays on the newest line while the meeting runs and shows the sentence still being spoken at the end (the dark caption only shows on the notes tab). Scrolling up to read no longer jumps back down; new sentences gather in a "↓ N 句新内容" button.
- Changed: transcript search highlights matches in place (with "2 / 7" and up/down) instead of hiding the other lines, and also finds the misrecognised spellings the notes list for a name.
- New: notes show when things were said: topics as time ranges, a time beside each point and conclusion; click one to jump to that line. The status line shows the number of sentences and how far the notes have got ("纪要到 03:52").
- Changed: the collapsed card no longer asks "我刚走神了，错过什么？": it says "收起后新增 2 个议题、5 条要点" only when there is something new, and opens a list of it with times.
- Fixed: after the meeting ended, almost every point was marked "新"; "新" now only marks what a live update added, for a minute.
- New: while any Live Subs window is open (the notes window included) the app shows its name and menus in the top left, a Dock icon and a place in ⌘Tab: 纪要 (stop recording ⌘R, update notes now ⌘U, "收起后的新内容" ⌘J, copy notes, export ⌘E, meeting records ⌘0), 显示 (notes / subtitle bar / nothing, card ⌘1 / sidebar ⌘2 / side by side ⌘3, stay on top), 编辑 (copy, paste, search the transcript ⌘F), 窗口 and 帮助. With every window closed it lives in the menu bar only. Pasting a key with ⌘V now works.
- Changed: the notes window shows what it is doing instead of hint text: moving sound bars while nobody has spoken yet, a spinner with "已听到 N 句" and the notes' shape shimmering while the first version is written, and an "正在更新" pill plus a shimmer under the current topic while existing notes are updated; new points fade in.
- Fixed: installing the virtual microphone looked like it failed ("系统还没识别到"). The package installed fine, but macOS only loads a new audio driver after its audio service restarts; the same password prompt now restarts it. If the driver is already there but not loaded, the app offers "让系统认出它" instead of reinstalling.
- New: a sound test for the virtual microphone: the app plays a sentence into it, listens back and shows what the room will hear.
- New: a settings window with a sidebar (听 / 我说话也翻译 / 字幕条 / 会议记录) replaces the settings sheet; the virtual microphone is set up from a three-step checklist there and in the first-run guide.
- Changed: hold the right ⌥ key on its own to talk, instead of ⌥ Space (which other apps' launchers often use, and which types a space). Pressing another key while holding it cancels, so ⌥ + letter still types. It needs the "输入监控" permission; the app asks for it.
- New: speak-back can use Ming's voices through the Ling key, streamed as they are generated; without a key it uses the Mac's voice.
- New: meeting records show the notes (纪要 / 文字记录); a meeting recorded without notes gets a "生成纪要" button. Markdown and Word exports start with the notes.
- New: a live notes window, now the default display while listening: notes, the transcript and a caption line in one floating window that can be moved and resized anywhere (a small card under 360 px, tabs in between, notes beside the transcript from 760 px), never shows up in screen sharing, and remembers its frame. The menu bar panel and settings choose 实时纪要 / 字幕条 / 不显示; ⌃⌥S now cycles through them.
- New: live meeting notes. With a key, Ling updates the notes about every 45 s while the meeting runs (summary, topics with key points, a fishbone diagram where causes are discussed, conclusions and to-dos with how many lines back them, names and terms with their misrecognised forms) and rewrites them once over the whole transcript when it ends. Notes are saved with the meeting.
- New: with a key, finished sentences and speak-back are translated by Ling (names kept consistent through the notes' glossary); if Ling is busy or fails, that sentence falls back to Google, then to Apple's on-device translation. Partial text while someone is still talking stays on Google.
- New: Settings › AI 服务 takes your own Ling (ant-ling.com) API key. It is kept in the macOS Keychain, checked with a one-token request, and shown masked; without a key everything works as before.
- New: both shortcuts (talk, hide/show the subtitle bar) can be changed in settings: click and press new keys. Combinations without ⌃ or ⌘, system shortcuts and ones another app already uses are refused with a reason.
- Fixed: clicking the live notes window no longer brings the main or settings window forward or takes focus from the meeting app, and the notes window alone no longer puts the app in the Dock. The Dock icon reopens whichever window is open instead of always the main window; exporting from the main window opens the save dialog on it; quitting while a meeting is being recorded asks first; settings remember their position and last tab; the 窗口 menu lists the open windows.

## 2.0.0 — 2026-11-01

- New: spoken-language auto-detection across the installed on-device models; translation target follows the system language or a manual choice.
- New: menu bar panel, meeting records with Markdown / Word / SRT export, and a three-step first-run guide with a built-in sample video.
- New: hold ⌥ Space to speak; your words are translated and spoken into a virtual microphone, installed from the app.
- New: the subtitle bar shows up only while someone talks, tucks away into a dot, turns see-through when the pointer passes; ⌃⌥S shows or hides it.
- Improved: on-device recognition with macOS 26 SpeechAnalyzer (no audio leaves the Mac), new icon, DMG installer.
- Improved: the subtitle bar is only as tall as the translation needs.
- Fixed: after a language switch the start of the sentence was sometimes lost.
- Fixed: when translation fails, your untranslated words are no longer spoken into the room.
