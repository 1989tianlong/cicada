# Changelog

One section per release, newest first; one version covers every platform. `scripts/release.sh`
writes it from the `feat:` and `fix:` commits since the last tag, grouped by platform (the commit's
scope), and the release workflow publishes it as the release notes and ships only the platforms in
it. Lines under `## Unreleased` become the release's summary. The Chinese changelog for users is `site/changelog.json`.

## 1.0.0 — 2026-11-03

The first public release. Cicada turns whatever your Mac plays into live translated subtitles and meeting notes, keeps each meeting as a bilingual record, and speaks what you say back into the meeting in the other side's language.

### Highlights

- Live bilingual subtitles for any app that plays sound, with on-device speech recognition that detects the spoken language
- Live meeting notes with a Ling key: a summary, topics, conclusions, to-dos, names and terms, and a fishbone diagram when causes are discussed
- Meetings saved as bilingual records with the notes beside the original lines, exported to Markdown, Word or SRT, and ended by themselves when the call hangs up or goes quiet
- Interpreting: hold right ⌥ to talk, and Cicada speaks the translation into the meeting through BlackHole 2ch with a Ming voice, a Mac voice or your own, switching the system mic for you
- Speaker identification (experimental) tells the other side's voices apart and, with a Ling key, fills in their names
- The live notes window stays out of screen sharing unless you choose to show it
- English, Japanese, Korean and Chinese interface, a four-step first-run guide, and in-app updates checked against each release's SHA-256
