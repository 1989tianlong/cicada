---
name: room-test
description: Measure Cicada's room microphone for real on the Mac — echo from the speakers, people at the table talking in the gaps and over the online side, music, headphones — with an ESP32 speaker standing in for a person at the table, and score each round. Use after any change to 打开麦克风, the room mic, EchoGate / EchoMatch, voice activity or the room recognizer, or for "测回声", "测会议室麦克风", "混合会议实测", "抢话测试".
---

# Room test

How the 打开麦克风 change (cb7762c) was measured. The Mac is the reference; Windows and Linux VMs have no speakers or mic, so their rounds are UI and state only (`cicadactl mic on`, `roomechosim`).

## The rig

- **Online side:** `mac.wav` (five English sentences, 10 s apart) from the MacBook's speakers, through `afplay`.
- **Table side:** `table.wav` (six Chinese sentences: three in the Mac's gaps, three over its speech) from the M5Stack StopWatch's speaker: `~/workshop/15.experiment/m5-stopwatch/tablevoice/tv.py play <wav> --at <utc>` (prints START/END). Different languages, so each record line says which side it came from.
- **Where:** the ESP32 about 10 cm from the MacBook Pro's mics, which sit under the left speaker grille near the hinge (by Esc), speaker facing it, not on the right grille. At 30 cm it reaches only −22 dB peak and half the table lines are lost to level alone. Its volume is already the ceiling (255).
- The ESP32 belongs to the `esp32-stopwatch-meeting-mic-test` session: message it before using the port (one `tv.py` at a time) and when done. Flashing it is that session's user's call.
- `scripts/clips.py` writes the clips (and `music.wav`); `scripts/audio.swift` sets the output device and the mic's input level; `scripts/round.sh` runs one round and scores it. Both are built into `$WORK` on first use.

## Before the first round

- `ListAgents`: tell the sessions on this repo you hold the dev build, the speakers and the mic; nobody else rebuilds or drives `build/Cicada.app` until you say so. Build it yourself and check the panel's `main @ <commit>` line is yours.
- Nothing else makes sound: quit the release Cicada (`osascript -e 'quit app id "com.wquguru.cicada"'`; if it hangs, `kill -TERM`), shut simulators (`xcrun simctl shutdown all`). `pmset -g assertions | grep -i audio` lists who plays or records. Ask before closing anything the user may be using.
- `audio list`: output must be the MacBook speakers and the MacBook mic's level about 0.5. **AirPods take the output when they connect** (and the clips then play in the user's ears): `round.sh` forces the output every round; check it again after any pause, and ask the user before playing out loud.
- The terminal has no microphone permission: `ffmpeg -f avfoundation` records zeros. Judge the mic only through the app (`hybridState`, the record).

## Rounds

`scripts/round.sh <label> [mac|music|none] [volume]`, env `OUT` (`BlackHole` = headphones: nothing reaches the room), `ECHO` (`roomEcho`, default off), `GATE`, `TABLE`. Each round is about 75 s and prints, for example:

```
== speakers56: mac=5 room=3 echo_dropped=0 english_room=0 table: 空100% 抢0% 空75% 抢0% 抢20% 空100%
   echo=true [during=7.8s p80=0.0943 quiet=4.8s floor=0.0043]
```

`english_room` is online speech that got into the room's record (echo). `空` is a table sentence in a gap, `抢` one over the online side, with the share of its characters found. `echo=` is what EchoGate measured: speakers about ×20 at 56 %, ×6 at 25 %, headphones about ×1.

The pass line (2026-11-06, MacBook Pro 14):

| Round | Command | Pass |
|---|---|---|
| Speakers 25 / 56 / 100 % | `round.sh s25 mac 25` … | `english_room` 0; gaps ≥ 75 % |
| Music | `round.sh music music 56` | table ≥ 60 % (gaps and over) |
| Headphones | `OUT=BlackHole round.sh hp mac 56` | `echo=false`; over ≥ 90 % |
| Then speakers again | `round.sh s56b mac 56` | `english_room` 0 (the measurement starts over) |
| Table alone | `round.sh alone none` | 6/6 |

Lines over the online side are lost on speakers by design (the gate). Run a round twice before believing a single bad cell: the ESP32 is quiet and one round varies.

Also: `lsctl roomMicSilent:on` then `mic:on` shows 麦克风没声音 after about 10 s (log `room mic: silent since it started`, then `still silent`); `roomEchoSim:<on|off|real>` fixes the measurement for UI work.

## After

`lsctl mic:off`, `stop`, `roomEcho:off`, `roomGate:on`, `roomMicSilent:off`; output back to what the user had; volume back; tell the ESP32 session and the repo's sessions you're done. Put the numbers in the commit message.
