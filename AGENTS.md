# AGENTS.md

Live Subs is a macOS menu bar app that turns whatever the Mac is playing (streams, videos, meetings, voice rooms) into live translated subtitles, keeps every meeting as a bilingual transcript, and can translate what you say back into the room as speech.

## Scope (deliberately small)

- Three surfaces, nothing more: the **menu bar panel** (on/off, heard language, translate-to language, "我说话也翻译", subtitle bar display mode, meeting records, quit), the **subtitle bar** on screen, the **main window** (meeting records) and a **settings window** (sidebar: 听 / 我说话也翻译 / 字幕条 / 会议记录). First launch shows a three-step **onboarding** window (permissions, try the sample video, speaking).
- Listening: system audio (Core Audio process tap, our own process excluded) → spoken-language detection across installed on-device models → on-device transcription (`SpeechAnalyzer` / `SpeechTranscriber`) → translation (Google endpoint) → subtitle bar. Every confirmed sentence goes into the live meeting record.
- Language detection compares confidence: the same 3–6 s clip after a pause is transcribed by every installed model; a winner needs confidence ≥ 0.6 and a 0.08 lead; the first detection or a 0.30 lead switches at once, otherwise two agreeing detections. After a switch the last 8 s are replayed into the new model.
- "Follow system" translates into the first system language that differs from the source language.
- Subtitle bar: shows only while someone talks (auto) or always; tucks into a dot after 2/4/8 s of quiet; fades to 15% and stays click-through while the pointer passes over it; editable after the pointer rests 0.6 s (drag to move, drag the corner to scale, double-click resets); ⌃⌥S (changeable) hides/shows. Position, width and size are remembered per display.
- Speaking: hold the right ⌥ key alone (a listen-only event tap, needs Input Monitoring; any other key while held cancels the press as a chord) or a user-chosen combination (Carbon hotkey, no permission) → microphone → one `SpeechAnalyzer` per press, finished with `finalizeAndFinishThroughEndOfInput` → translate into the room's language → system voice → the chosen output device (a virtual microphone). The virtual microphone is BlackHole 2ch, installed from the app: download the official notarized package, check its pinned SHA-256, run `installer` and restart `coreaudiod` in one standard administrator prompt (the package only copies the driver and asks for a reboot; Core Audio loads a new HAL plug-in only when it restarts). Then a loopback sound test: speak a fixed English phrase into the device, record its input side, transcribe it (`LoopbackTest`). The checklist UI (`MicSetupCard`) is shared by onboarding step 3 and settings. We never bundle the GPL driver.
- Meeting records: one folder per meeting, `session.json` + `system.m4a` (+ `mic.m4a`); empty meetings are dropped; export to Markdown, Word (`.docx` via `NSAttributedString`) and SRT. Speaker labels are only "对方" (system audio) and "你" (microphone): no diarization yet.
- Shortcuts (`Shortcuts.swift`): talk and subtitle-bar toggle are recorded in settings (`ShortcutField`). A combination must include ⌃ or ⌘ (⌥/⇧ alone types characters; bare F keys are brightness/volume), must not be a system shortcut (`CopySymbolicHotKeys`) or held by another app (Carbon refuses to register it).
- Nothing the user does needs the Terminal. When a feature request fits none of the above, push back before adding UI.

## Design

- Source of truth: the Design canvases in claude.ai (logo directions, onboarding, auto show/hide) and the app itself.
- Look: light grey ground `#F3F4F6`/`#F6F7F9`, white cards, ink `#15171C`, one accent orange `#E8552B` for "live" (dots, the speaking line, the icon). Text greys `#5A5F6B` / `#6B7080` (they pass 4.5:1 on white).
- Logo C: white sound bars turning into lines of text on an orange squircle. The app icon is drawn by `Sources/LiveSubsIcon`; the in-app mark (`BrandMark`) and the menu bar template glyph (`BrandImage.menuBar`, 40% when paused) are drawn in code in `Onboarding.swift`.
- Copy is Chinese, short: one line of grey helper text at most.

## Layout

- `Package.swift`: SwiftPM, macOS 26+, Swift 5 language mode, no dependencies.
- `Sources/LiveSubs`: the app. Engine files are UI-free: `SystemAudioTap`, `AudioRouter` (resample, feed, ring buffer, recording), `LanguageDetector`, `ListenEngine`, `SpeakEngine`, `Shortcuts` (Carbon `HotKey`, right-⌥ `RightOptionKey`), `Translator`, `VirtualMic`, `SessionStore` (+ exports). UI: `Overlay` (subtitle bar), `Views` (panel, main window), `SettingsWindow` (settings + the virtual mic checklist), `Onboarding` (+ sample player, brand mark), `AppModel` (wiring, status item, windows, debug control, `@main`). `DMGBackground` draws the installer background; `DevBuild` tells dev from release.
- `Sources/LiveSubsIcon`: CLI that renders the icon set (`--dev` adds the DEV band).
- `Resources/`: `Info.plist`, `sample/` (the 7 s onboarding clip, made by `scripts/make-sample.sh`), `dmg/DS_Store` (installer window layout).
- `scripts/build.sh`: builds `build/LiveSubs.app`. Without `RELEASE=1` it is a **dev build**: "Live Subs Dev", bundle id `com.wquguru.cicada.dev`, `LiveSubsDev` = `branch @ commit[+]` in Info.plist; "DEV" beside the menu bar glyph, a DEV badge and the stamp in the panel, a DEV band on the icon, its own settings, permissions, `~/Library/Application Support/LiveSubs Dev` and log `/tmp/livesubs-dev-debug.log`. Both builds are signed ad hoc with a fixed designated requirement (the bundle id) so rebuilding keeps the system-audio and microphone permissions. Don't change the release bundle id `com.wquguru.cicada`: permissions are tied to it.
- `scripts/package.sh`: `RELEASE=1` build (refuses any other bundle id) → `LiveSubs-<version>-macOS-AppleSilicon.dmg` / `.zip` + `checksums.txt`. The DMG background is drawn by the app (`LiveSubs --render-dmg-background out.png <scale>`); the window layout is `Resources/dmg/DS_Store`, made by Finder via `scripts/dmg-template.sh` — rerun it after changing the window, icon positions or background, and keep `DMGBackground.swift` in step.
- `tools/`: test helpers (remote control, synthetic mouse/keys, window capture, transcription check); see `tools/README.md`.

## Commands

```bash
swift build                          # debug build
scripts/build.sh && open build/LiveSubs.app          # dev build (Live Subs Dev)
RELEASE=1 scripts/build.sh           # release build (com.wquguru.cicada)
scripts/package.sh                   # DMG + zip + checksums in build/
scripts/make-sample.sh               # regenerate the onboarding sample clip
```

Debug control: dev builds always accept commands on the distributed notification `com.wquguru.cicada.debug` (release builds only with `defaults write com.wquguru.cicada debug -bool true`, which also logs transcript text). Send them with `tools/lsctl` (`start`, `stop`, `open`, `panel`, `onboarding:<step>`, `samplePlay`, `speakFile:<audio>`, `settings:<listen|speak|overlay|records>`, `micTest`, `micNext`, `talkKey:<right|keyCode:mods>`, `toggleKey:<keyCode:mods>`, `shortcuts`, `place:x,y,w,font`, `frame`, `overlayState`, `export:<dir>` …).

Release: `scripts/release.sh <x.y.z>` (clean `main`, a `## x.y.z — <today>` section in `CHANGELOG.md`) bumps `Resources/Info.plist`, commits, tags `v<x.y.z>` and pushes; `.github/workflows/release.yml` (runner `macos-26`) builds the tag, checks it matches Info.plist and publishes the DMG, zip and checksums with notes from `scripts/release_notes.sh`. `build.yml` runs on pull requests and on demand only: macOS minutes are expensive for a private repo.

Only Command Line Tools are required (no Xcode project). Do not add an `.xcodeproj`.

## Verifying changes

Run the app and check the behaviour, not just the build. The pattern used so far: dev build, `tools/lsctl` to drive it, `afplay Resources/sample/sample.m4a` (or `say -o` clips) as the "someone talking" input, read `/tmp/livesubs-dev-debug.log`, screenshot windows with `screencapture -l <id>` (`tools/winall`). Synthetic mouse/key events (`tools/mouse`, `tools/key`, `tools/toggle-key`) need the terminal to have Accessibility access. Synthetic keys reach every app: another app's launcher may take ⌥ Space. The real microphone, the BlackHole install (password), granting Input Monitoring and a Mac without permissions need a person.

TODO: unit tests for the pure parts (language-code mapping, detection scoring, SRT/Markdown export). Swift Testing under Command Line Tools needs extra framework search paths (see cameo's `scripts/test.sh`).

## Conventions

- Keep files small and single-purpose; match the existing naming and comment density (comments say why).
- UI and engine state are `@MainActor`; audio callbacks never touch app state directly (they hand buffers to `AudioRouter`'s queue).
- No third-party dependencies; system frameworks only.
- User data: `~/Library/Application Support/LiveSubs/Sessions` and `UserDefaults` (`sourceMode`, `target`, `speakEnabled`, `speakFrom`, `speakTo`, `speakOutput`, `recordAudio`, `overlayAuto`, `overlayHideAfter`, `overlay.<screen>`, `lastDetected`, `onboarded`, `talkKey`, `toggleKey` as `keyCode:carbonModifiers`).
- Add a line to `CHANGELOG.md` with every user-visible change. Keep `README.md` and `README.zh-CN.md` in step.
- Commit in coherent batches with a short imperative subject.
