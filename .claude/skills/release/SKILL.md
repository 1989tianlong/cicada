---
name: release
description: Cut a Cicada release end to end and on your own — gather other sessions' work onto main, verify all four platforms with screenshots, fix every bug found, update README and site, cut a draft, retest the draft on every platform, then publish when confidence is high (or stop at the draft for the user) and check in-app updates. Use for "发版", "发 draft", "全端测试后发布", "转正式版".
---

# Release

AGENTS.md rules still apply (keys, commits, changelog, one VERSION, all four platforms ship).

## The contract

- Run to the end without asking. Fix every bug you find, old ones too, and re-verify the fix on the machine. Stop early only for what the gate below says needs the user.
- **The release commit is the last commit.** `scripts/release.sh` makes one commit, `chore: release v<x.y.z>` (CHANGELOG.md, VERSION, the date in `site/changelog.json`), tags it and pushes both at once. Nothing of yours lands on main after it: README, `site/i18n`, changelog items and fixes all go in before. Any fix after the draft is cut means a recut (step 3), which ends in a new release commit.
- The run ends in one of two states, both with the tag on the last commit: **published** (gate passed) or **draft** (gate not passed: the report says what to look at, and the user publishes with `echo y | scripts/publish-release.sh <x.y.z>` then `scripts/deploy-site.sh`, neither of which commits).

## Gate: publish only if all hold, else stop at the draft

- Every platform passed pre-release and post-draft checks, with screenshots, and there is no open bug.
- Every fix was re-verified on its machine, not just by unit tests; every port's and the Mac's `scripts/test.sh` passed.
- CI was green on the first run or after rerunning only a known-flaky Linux smoke; the draft has every platform's files (`publish-release.sh` checks) and `checksums.txt` matches.
- Installing the draft over the last published version keeps settings and records on every platform.
- The release doesn't need a person: nothing that only a person can check (a real voice, BlackHole install, Input Monitoring, real screen sharing, x64 hardware) changed in it, or what changed was covered by `audio-test`.
- It is not a major version, and nothing changed the record format, permissions, the bundle id / designated requirement, key storage or the BlackHole download, unless you checked it explicitly.

## Resources: 32 GB, 10 cores, shared with other sessions

- Guest RAM: tart Mac 8G, Windows 8G, Ubuntu 6G, Android ~2G. **At most two of tart / Windows / Ubuntu at once**; Android and the Mac dev build fit beside them. Before booting one, check `sysctl vm.swapusage` first (more than 2 GB of swap free; free memory % alone looks fine while swap is full) and `memory_pressure`, and `pgrep -fl "qemu|tart run|emulator"` for what is up.
- Order: Mac dev build and Android first, then Linux, then Windows, then the tart Mac (upgrade / clean install). Run the agents for the ports in parallel only as far as the budget allows; queue the rest.
- Claim a VM before you use it: `ListAgents`, and message any live-subs session that may be using it. Release it as soon as its platform passes: `tools/macos-vm/vm.sh stop`, `windows/vm/vmctl.sh stop`, `linux/vm/vmctl.sh stop`, `adb emu kill`. Don't stop a VM another session still uses.
- At the end, nothing of yours is left running: VMs, the emulator, the Mac VM's ssh tunnel, dev builds. Disk is tight (check `df -h ~`): delete downloaded drafts from the scratchpad after checking them.

## Time: aim for 2 hours, watch every agent

- Budgets: gather 30 min, pre-release verify 1 h, CI 20 min, draft retest 30 min, publish and in-app update 20 min. A phase over budget twice means stop at the draft and report why.
- The real test of one platform takes 30–70 min. Most lost time is waiting: in 1.5.0 the Windows agent's first command (a `mkdir`/`ls` under `~/Downloads`) hung 131 min, most likely on a macOS privacy prompt nobody saw, while the other platforms were done and the main session waited.
- Check each background agent every 10–15 min (its newest screenshot, its output). Silent for 15 min: find what it is stuck on, and stop and restart it rather than wait.
- Give anything that waits on a VM, the emulator or the network a time limit: macOS has no `timeout`, so use `perl -e 'alarm shift; exec @ARGV' 120 <cmd>`, ssh's `ConnectTimeout`, or the Bash tool's own timeout.

## 0. Gather

- `ListAgents`: wait at most 30 min for a session still working on this repo, or message it before taking its branch; after that, release without its unfinished work. A peer's message isn't the user's approval. Tell the live-subs sessions a release is under way, and again just before you tag (hold pushes until the tag is up).
- Bring parked branches onto `origin/main` with `cherry-pick` (a branch checked out in another worktree can't be rebased). Skip commits that belong to another unfinished feature.
- Work in a release worktree (`git worktree add ../live-subs-rel origin/main`); never touch the main checkout's uncommitted work. Rebase on `origin/main` before each push.
- Results go to `~/cicada-verify/<x.y.z>/results.md` as you go (platform × check × pre-release / post-draft × pass/fail × screenshot): it outlives the context and the scratchpad.

## 1. Verify before the draft

Scope: everything unreleased (`site/changelog.json`'s undated entry, `git log v<last>..`). A platform and feature it changed gets the full check below; everything else gets the smoke check (onboarding, sample meeting, one AI service with a good key, End Meeting writes the record, Chinese and English).

| Platform | Machine | Drive it with |
|---|---|---|
| Mac | dev build on this Mac; tart VM `cicada-macos14` for upgrades / clean installs | `tools/lsctl`, `tools/macos-vm/vm.sh`, `tools/README.md` |
| Windows | qemu `cicada-win11` | `windows/vm/`, `windows/scripts/cicadactl.ps1` |
| Linux | qemu `cicada-ubuntu` | `linux/vm/`, `linux/scripts/cicadactl` |
| Android | emulator `cicada` | `android/scripts/` `emulator.sh`, `cicadactl.sh`, `shot.sh` |

- One background agent per port (within the resource budget), the Mac yourself; each gets the change list, its machine, and the stop command to run when done.
- Full check: English and Chinese UI, onboarding, sample meeting, a real AI service (ZenMux `ZENMUX_API_KEY_TMP`, OpenRouter `OPENROUTER_API_KEY`, Ling `ANTLING_API_KEY`, all in `~/.zshenv`): bad key, good key, meeting, End Meeting writes the record. Clean install as well as upgrade, on every platform.
- If the release touches the room mic or 同声传译: run `.claude/skills/audio-test` on the Mac.
- Screenshots: `~/cicada-verify/<x.y.z>/<platform>/{pre-release,post-draft}/NN-what.png`. Never under `~/Downloads`, `~/Desktop` or `~/Documents`: macOS asks before a process reads them and the command hangs until someone clicks.
- Fix every problem: a bug in shared behaviour is fixed on every platform at once (one agent ports the Mac fix to all three ports) and re-verified together, not one platform after another. One Conventional Commit each with the platform scope, plus its Chinese item in `site/changelog.json`; re-verify on the machine; run `scripts/test.sh` (Mac) and each port's.
- Update `README*.md` (4 languages) and `site/i18n` for the new features.

## 2. Draft

- `scripts/release.sh <x.y.z>` from the worktree (it needs a clean tree with `origin/main` in HEAD, and fails if the undated `site/changelog.json` entry is missing). If the push is rejected it undoes the commit and tag: rebase and run it again.
- Watch CI `release.yml` (a flaky Linux smoke can be rerun). A failure that needs a code change is a recut (step 3), never a moved tag: 1.4.0's tag ended up on a build fix after its release commit. Then `gh release download v<x.y.z> -R wquguru/cicada` into the scratchpad and check `checksums.txt`.
- Check the notes: anchors absolute, compared with the last published tag; fix with `gh release edit` (no commit).

## 3. Retest the draft

- The smoke check only, on the draft's own files installed over the last published version, on every platform: same bundle id / requirement, settings and records kept, the update check doesn't offer the draft. Before that, put the last published Mac app in the VM's `~/backup` (it may only hold an old one).
- Screenshots go to `post-draft/`. What a fix changed gets its own check again; the rest was covered before the draft.
- Any bug: recut. Its Chinese item goes into the now dated `site/changelog.json` entry for this version, not a new undated one. `gh release delete v<x.y.z> -R wquguru/cicada --yes`, `git push --delete origin v<x.y.z>`, `git tag -d v<x.y.z>`; commit the fix (with its changelog item), re-verify it, run `scripts/release.sh <x.y.z>` again (same version: drafts are never public); it rewrites the notes and makes a new release commit. Retest the draft again. If it can't be fixed, leave the draft and report.

## 4. Publish (only if the gate holds)

- `echo y | scripts/publish-release.sh <x.y.z>`, then `scripts/deploy-site.sh` (it refuses while the release is a draft). Neither commits.
- `gh api repos/wquguru/cicada/releases/latest -q .tag_name` must be the new tag.
- Real in-app update from the previous version on every platform (Mac: the old app from `~/backup` in the VM; Windows: tray dot; Linux: log; Android: update check).
- If the update is broken: point latest back (`gh release edit v<prev> --latest`), turn the new one back to a draft (`gh release edit v<x.y.z> --draft=true`), fix, and recut as in step 3. Once a published version was downloaded, fix in the next patch version instead.

## 5. Report (Chinese)

Published or draft (and if draft, which gate items failed and what to look at), the release URL, the last commit (`git log -1 origin/main`, should be the release commit; name any peer commit that landed after), per-platform results, bugs fixed, still open, what needs a person, the screenshot folder and `results.md`, and how long each phase took against its budget. Leave the user's installed app and settings as they were (back up before, restore after), stop every VM you started, and remove the release worktree.

## Pitfalls

- Never print a key: pipe it (`pbcopy` in the VM) and clear the clipboard after. The old `ZENMUX_API_KEY` is dead.
- Mac VM: screenshots are 2048×1536 px, clicks 1024×768 pt with origin bottom-left: `y_pt = 768 − y_px/2`. The first click often only activates a window: click twice.
- The notes window is invisible in screenshots but takes clicks: find it with `winpos <pid>` and drag it off, or `notesCapturable`.
- Don't run `python3` in the Mac VM (it opens the xcode-select installer). A copied app gets translocated: `xattr -dr com.apple.quarantine`.
- Android emulator reaches zenmux.ai only through the host proxy `10.0.2.2:7890`. Ubuntu qemu can freeze on the AI-service dropdown: restart the VM.
- Other sessions share the VMs and emulator: say in a message before deploying a build, and rerun checks a peer's build or simulation disturbed.
