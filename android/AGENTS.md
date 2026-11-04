# AGENTS.md (Android)

The Android port: listening only. The root `AGENTS.md` applies too (Ling key, `LingClient`, no third-party dependencies, the Mac app as the reference, one `VERSION`). Commands, layout and how to verify are in `README.md`; the plan is `docs/android-plan.md`.

- Kotlin and the Android framework only: no AndroidX, Compose or other libraries; UI in code, no XML layouts. `core` is plain JVM and must build and test on the Mac.
- The key: `AIKey` in `core/.../Ling.kt`, the `ling-api-key` file in the app's private folder, kept out of backups; every Ling or Ming call goes through `LingClient`.
- The overlay is `FLAG_NOT_FOCUSABLE` and `FLAG_SECURE` unless 共享屏幕时让对方看到 is on.
- Shared UI text comes from `Resources/*.lproj/Localizable.strings`; Android-only text is in `app/src/main/strings/`. Run `python3 scripts/strings.py` after changing either.
- Verify with `scripts/test.sh`, then in the emulator with `scripts/cicadactl.sh`. System consent dialogs, vendor background limits and a real microphone need a person.
- No release build ships until release signing exists; never sign a release with the debug key.
- Commits use the `(android)` scope: `feat(android):` / `fix(android):` are this platform's release notes.
