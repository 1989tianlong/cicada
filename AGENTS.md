# AGENTS.md

Cicada (知了, formerly Live Subs): a macOS menu bar app that turns what the Mac plays into live translated subtitles and meeting notes, keeps each meeting as a bilingual record, and speaks what you say back into the room in their language.

## Scope

- Surfaces: menu bar panel, live notes window (default) or subtitle bar while listening, main window (meeting records), settings, four-step onboarding (permissions, Ling key, sample video, speaking). A request that fits none of them gets pushed back before any UI is added.
- Nothing the user does needs the Terminal.
- Listening: Core Audio process tap → on-device language detection and `SpeechAnalyzer` → translation. Speaking: hold right ⌥ or a shortcut → mic → Ming (with a Ling key) or on-device + translation → voice → BlackHole 2ch virtual mic.

## Hard rules

- The Ling key lives only in the 0600 `ling-api-key` file (`AIKey`): never UserDefaults, logs or exports.
- Every Ling call goes through `LingClient` (rate gate, priorities, `thinking: disabled`, content in the system message). Partial text is translated by Google, never Ling.
- Never speak untranslated text into the room. Never bundle the GPL BlackHole driver; download it and check its pinned SHA-256.
- The notes window is a non-activating panel with `sharingType = .none`: it must never take focus or show in screen captures.
- UI and engine state are `@MainActor`; audio callbacks hand buffers to `AudioRouter`'s queue.
- Don't change the release bundle id `com.wquguru.cicada` or the ad-hoc designated requirement: permissions are tied to them.
- No third-party dependencies, no `.xcodeproj`; Command Line Tools only.

## Design

- Ground `#F3F4F6`, white cards, ink `#15171C`, one accent `#E8552B` for "live", greys `#5A5F6B` / `#6B7080`. Design canvases on claude.ai and the app itself are the source of truth.
- Copy is Chinese and short, at most one grey helper line. Chinese text is the localization key; `Resources/{en,ja,ko}.lproj` translate it. SwiftUI literals localize themselves; other UI strings use `L("…")`; never `L()` prompts, logs or stored values. After changing UI text run `python3 scripts/strings.py` (`--write` adds TODOs), and check the English UI, which runs wider.
- The logo geometry is kept in step in `CicadaLogo` (`Onboarding.swift`), `Sources/LiveSubsIcon` and `site/icon.svg`; then rerun `scripts/site-images.sh`.

## Layout

- `Sources/LiveSubs`: the app, one concern per file. Engines are UI-free (`ListenEngine`, `SpeakEngine`, `SpeakTest`, `Notes`, `Translator`, `Ling`, `VirtualMic`, `SessionStore`, `Updates`…); `AppModel` wires them and holds the debug commands. Settings keys: `AppSettings` in `Settings.swift`.
- `Sources/LiveSubsIcon`: renders the icon set. `site/`: the website, built by `scripts/site.py`.
- The site is Chinese at `/`, English / Japanese / Korean under `/en/` `/ja/` `/ko/`; every `{{t.key}}` comes from `site/i18n/<lang>.json`. `start.html` is the setup page; its `img/start/` screenshots come from the app in each language. `tools/`: test helpers. `Tests/LiveSubsTests`: unit tests for the pure parts.

## Commands

```bash
scripts/test.sh                        # AGENTS.md check + unit tests
scripts/build.sh && open build/Cicada.app   # dev build: own bundle id, settings, log
RELEASE=1 scripts/build.sh             # release build
scripts/package.sh                     # DMG + zip + checksums
scripts/release.sh <x.y.z>             # needs a dated CHANGELOG section; CI publishes the tag
```

## Verifying

- Run the app and check the behaviour, not just the build; check the English UI too.
- Drive the dev build with `tools/lsctl` (commands and testing tips in `tools/README.md`; the source of truth is `AppModel.debugCommand`). Use `afplay Resources/sample/sample.m4a` or `say -o` clips as input and read `/tmp/livesubs-dev-debug.log`.
- A real voice, the BlackHole install, Input Monitoring and a Mac without permissions need a person.

## Conventions

- Match the existing naming and comment density; comments say why.
- Every user-visible change gets a `CHANGELOG.md` line and a matching `site/changelog.json` item; keep `README.md` and `README.zh-CN.md` in step.
- Commit messages are English only and follow Conventional Commits (`feat:`, `fix:`, `docs:`, `build:`, `refactor:`, `test:`, `chore:`).
- This file stays under 6 KB with these sections; `scripts/check-agents.py` enforces it in `scripts/test.sh`, CI and the pre-commit hook. Implementation detail belongs in code comments, not here.
