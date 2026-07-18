# Known macOS space hogs — tier, reclaim mechanism, traps

Read during classification. Read **again** before executing anything involving
Docker, Xcode, Homebrew, or the Trash — those four have mechanisms where a naive
`rm` either silently fails to free space or destroys something.

## Contents

- [Two things that are never yours to delete](#two-things-that-are-never-yours-to-delete)
- [Docker — the biggest trap](#docker--the-biggest-trap)
- [Xcode / iOS](#xcode--ios)
- [Package managers & build caches (Tier 1)](#package-managers--build-caches-tier-1)
- [Applications & models (Tier 2)](#applications--models-tier-2)
- [Tier 3 — real data](#tier-3--real-data)
- [Time Machine local snapshots](#time-machine-local-snapshots)

---

## Two things that are never yours to delete

**The Trash.** Emptying it is a permanent deletion of files the user may still
want to inspect, and it is not an action you take on their behalf — even if they
approve it. Report `~/.Trash` size, tell them it's there, and let them empty it
in Finder themselves.

**Anything requiring `sudo`.** `/private/var`, `/Library/Caches`, system logs,
other users' homes. This skill scans without sudo and reports these as blind
spots. `sudo rm -rf` with one mistyped character is an unbootable machine, and
the few gigabytes it buys are not worth that trade. If the user pushes, explain
the reasoning and point them at Apple's own **Storage Management** panel, which
does this safely.

---

## Docker — the biggest trap

Docker on macOS keeps everything inside one file: `Docker.raw`, the virtual disk
of the Linux VM. Three things about it will mislead you.

### 1. Find where it actually is

Users relocate it. Don't assume the default.

```bash
python3 -c "import json;print(json.load(open('$HOME/Library/Group Containers/group.com.docker/settings-store.json')).get('DataFolder',''))"
```

Empty output means the default: `~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw`

### 2. It is sparse — `ls` will lie to you

```
ls -lh Docker.raw  →  228G    # the size it is ALLOWED to grow to. Meaningless.
du -sh  Docker.raw  →  7.9M   # blocks actually on disk. This is the truth.
```

Finder shows the same misleading 228G. Users panic about this. Reassure them.

### 3. `docker prune` does NOT shrink the file

This is the part that wastes everyone's afternoon. `docker builder prune -af` and
`docker system prune -af --volumes` free space *inside* the VM's filesystem. On
macOS the `Docker.raw` file on the host **stays exactly as large as it was.** You
run the command, it reports reclaiming 19GB, and `df` doesn't move.

**Before proposing anything, find out what's actually in there:**

```bash
docker system df
```

If it reports `0` images, `0` containers, `0` local volumes and the space is all
build cache, then nothing of value is inside and a full purge is free.
If there are volumes, **stop** — volumes hold databases and user data. That's
Tier 3, and it needs a per-item conversation.

**The mechanism that actually shrinks the file:**

Docker Desktop → **❓ help icon in the top-right toolbar** → **Troubleshoot** →
**Clean / Purge data**.

As of Docker Desktop 4.80 Troubleshoot is *not* in the Settings sidebar. Users
will look there, not find it, and get stuck. Point them at the help icon.
Don't send them to "Reset to factory defaults" (wipes their settings too) or
"Uninstall".

**Manual alternative** — only when `docker system df` showed nothing worth
keeping. Docker Desktop recreates an empty image on next launch.

1. Quit Docker Desktop completely. Deleting the file while the daemon holds it
   open corrupts it.
2. Confirm it's down: `pgrep -fl "Docker Desktop"`
3. `rm -rf <DataFolder>/Docker.raw`
4. Relaunch Docker Desktop.

---

## Xcode / iOS

| Path | Tier | Notes |
|---|---|---|
| `~/Library/Developer/Xcode/DerivedData` | 1 | Usually the single biggest win on a dev Mac. `rm -rf .../DerivedData/*`. Next build is slow, nothing else. |
| `~/Library/Developer/Xcode/iOS DeviceSupport` | 1 | Symbol caches, one folder per device+OS. Regenerated (slowly) next time that device is plugged in. |
| `~/Library/Developer/CoreSimulator/Devices` | 2 | Simulator contents. Reclaim safely with `xcrun simctl delete unavailable` — drops only simulators whose runtime is gone. |
| `/System/Library/AssetsV2/com_apple_MobileAsset_iOSSimulatorRuntime` | 2 | The real bytes of installed simulator runtimes (compressed dmgs, often 8G+ each). The mounted volume they back — `/Library/Developer/CoreSimulator/Volumes/iOS_*` — always reads **~98% full**; that is its sealed, read-only, sized-to-fit normal state, not a problem, and `df` alarms about it are false alarms. `du -x` won't count the mount (correct — it would double-count the dmg). List: `xcrun simctl runtime list`. Reclaim: `xcrun simctl runtime delete <id>`. **Never `rm` either path.** |
| `~/Library/Developer/Xcode/Archives` | **3** | **Not build junk.** Holds the dSYMs that symbolicate crash reports from builds you shipped to users. Once deleted, production crash logs are permanently unreadable. Only safe if the app was never released. |
| `/Applications/Xcode.app` | 2 | 15GB+. Only if genuinely unused — reinstalling is an hours-long download. |
| `/Library/Developer/CoreSimulator/Profiles/Runtimes` | — | Simulator runtimes. Needs sudo → out of scope. Mention, don't touch. |

---

## Package managers & build caches (Tier 1)

All regenerable. The only cost is the next build being slower.

| Path | Reclaim |
|---|---|
| `~/Library/Caches` | Broad app cache. Safe to clear wholesale, but prefer naming the big subdirectories in the report so the user sees what they're agreeing to. |
| `~/Library/Caches/Homebrew` | `brew cleanup --prune=all` (also removes superseded formula versions) |
| `~/.gradle/caches`, `~/.gradle/wrapper` | plain `rm -rf`; gradle re-downloads |
| `~/.npm/_cacache` | `npm cache clean --force` |
| `node_modules` (scattered) | `rm -rf`, then `npm install` when they next touch the project. Find them: `find ~ -maxdepth 6 -name node_modules -type d -prune`. Warn that any project they're mid-work on will need a reinstall before it runs. |
| `~/Library/Caches/pip` | `pip cache purge` |
| `~/.cache/uv` | `uv cache clean` |
| `~/.pub-cache` | Dart/Flutter packages; re-fetched on `pub get` |
| `~/Library/Caches/CocoaPods`, `~/.cocoapods/repos` | Re-fetched on `pod install` / `pod repo update` |
| `~/go/pkg/mod` | `go clean -modcache` |
| `~/Library/Caches/go-build` | `go clean -cache` |
| `~/.cargo/registry` | Cargo re-downloads |

**Python virtualenvs** are the exception in this list — treat them as Tier 2.
They rebuild, but a `venv` can encode pinned versions that no longer resolve, and
re-creating one can quietly produce a different environment.

---

## Applications & models (Tier 2)

Recoverable, but the user pays a download or notices a behavior change. Always
state which.

| Path | Cost of deleting |
|---|---|
| `~/Library/Application Support/Google/Chrome/OptGuideOnDeviceModel` | Gemini Nano on-device model (~4GB). Chrome re-downloads it. To stop it coming back, disable the on-device model in `chrome://flags`. |
| `~/Library/Application Support/Claude/vm_bundles` | Sandbox VM image; re-downloaded on demand. |
| `~/Library/Android/sdk/ndk` | Only needed for native C/C++ Android work. Pure Kotlin/Java/Flutter projects never touch it. |
| `~/Library/Android/sdk/system-images`, `~/.android/avd` | Emulator images and virtual devices. Re-downloadable; any state saved inside an AVD is lost. |
| `~/.rustup/toolchains` | `rustup toolchain list`, then remove the ones they don't use. |
| Unused apps in `/Applications` | Obvious, but check size before suggesting — a 3GB app the user opens weekly isn't worth the friction. |

---

## Tier 3 — real data

Never on a blanket approval. Name each one, say what would be lost, confirm
individually — or just leave it and let the user decide later.

| Path | What's in it |
|---|---|
| `~/Library/Application Support/MobileSync/Backup` | **iPhone/iPad backups.** Often tens of GB. May be the only copy of a device's data. Delete only via Finder's device panel, and only if the user is certain. |
| `~/Library/Containers/<app-id>` | Sandboxed app data. The name looks like infrastructure; the `Documents/` inside is frequently the user's actual work. Open it up and look before saying anything about it. |
| `~/Library/Application Support/Google/Chrome/Default` | Browser profile: history, cookies, logins, extensions. Never `rm` this. Chrome's own **Clear browsing data** removes the cache without nuking the profile. |
| `~/Library/Mail`, `~/Library/Messages` | Local mail and message stores. |
| `~/Pictures/*.photoslibrary` | Photos library. Manage from inside Photos, never from the shell. |
| `~/Downloads` | Wildcard. Often full of re-downloadable installers and model weights — but also of things that exist nowhere else. Itemize the big files and let the user decide file by file. |
| `~/.Trash` | Report the size. Do not empty it. |

---

## Time Machine local snapshots

APFS keeps local snapshots on the internal disk, and `df` counts them as used.

```bash
tmutil listlocalsnapshots /
```

macOS purges them automatically under disk pressure, so they're rarely the real
problem, and they're a genuine safety net — the last line of recovery if a
cleanup goes wrong. Mention them, but reach for them last, not first.

If a backup destination exists, `tmutil latestbackup` shows the last real backup.
**No backup + any Tier 3 proposal = say so loudly, before the user chooses.**
