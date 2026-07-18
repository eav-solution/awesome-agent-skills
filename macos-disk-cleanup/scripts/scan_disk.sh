#!/usr/bin/env bash
#
# scan_disk.sh — one-shot read-only disk audit for macOS.
#
# This script NEVER deletes, moves, or modifies anything. It only measures.
# Every reclaim decision belongs to the human; this just gathers the evidence.
#
# Usage:
#   bash scan_disk.sh              # full scan
#   bash scan_disk.sh --fast       # skip the deep per-directory walks
#
# Expect 1-3 minutes on a full disk. `du` has to walk every inode; there is no
# shortcut. Run it once, read the whole output, then reason. Re-running it in a
# loop to "check one more directory" wastes minutes.

set -uo pipefail

# dotglob is the whole ballgame. `du -sh ~/*` silently skips every dotfile
# directory, and on a developer machine that is where the space actually hides
# (~/.gradle, ~/.cache, ~/.pub-cache, ~/.npm...). Turning it on here means the
# glob physically cannot repeat that mistake.
shopt -s nullglob dotglob

FAST=0
[[ "${1:-}" == "--fast" ]] && FAST=1

hr()  { printf '\n=== %s ===\n' "$1"; }
sub() { printf '\n--- %s\n' "$1"; }

# List a directory's children largest-first. -x keeps du on the current
# filesystem so it never wanders into /Volumes and double-counts an external
# drive as if it were internal.
children() {
  local dir="$1" limit="${2:-15}"
  [[ -d "$dir" ]] || return 0
  du -sh -x "$dir"/* 2>/dev/null | sort -rh | head -n "$limit"
}

# Print one path's size, silently skipping paths that don't exist. Used for the
# known-location probes below, most of which won't apply to any given machine.
probe() {
  local p="$1" note="${2:-}"
  [[ -e "$p" ]] || return 0
  local sz
  sz=$(du -sh -x "$p" 2>/dev/null | cut -f1)
  [[ -z "$sz" ]] && return 0
  printf '%-8s %s%s\n' "$sz" "$p" "${note:+  # $note}"
}

hr "1. BASELINE"
df -h /System/Volumes/Data
diskutil info /System/Volumes/Data 2>/dev/null \
  | grep -Ei "volume used space|container free space|file system personality"

hr "2. BACKUP STATUS"
# Not a space question — a safety question. Anything in Tier 3 is unrecoverable
# without a backup, so the human needs to know this before approving those.
# tmutil exits 0 with empty output when no destination is configured, so the
# exit code alone is not a usable signal — test the output.
TM_LATEST=$(tmutil latestbackup 2>/dev/null)
if [[ -n "$TM_LATEST" ]]; then
  echo "Time Machine latest backup: $TM_LATEST"
else
  echo "Time Machine: NO BACKUP FOUND (no destination configured, or never run)"
  echo "  -> Tell the user this BEFORE they choose, not after. Nothing in Tier 3"
  echo "     is recoverable on this machine."
fi
sub "APFS local snapshots (these occupy real space and df counts them as used)"
tmutil listlocalsnapshots / 2>/dev/null | grep -v "^Snapshots for" || echo "  none"

hr "3. HOME — top level (hidden dirs INCLUDED)"
children "$HOME" 25

hr "4. ~/Library breakdown"
children "$HOME/Library" 15
if [[ $FAST -eq 0 ]]; then
  for d in Developer Containers "Application Support" Caches; do
    [[ -d "$HOME/Library/$d" ]] || continue
    sub "~/Library/$d"
    children "$HOME/Library/$d" 10
  done
fi

hr "5. SYSTEM-LEVEL (no sudo — see BLIND SPOTS below)"
for d in /Applications /Library /opt /usr/local; do
  probe "$d"
done
sub "/Applications by app"
children /Applications 12

hr "6. KNOWN LOCATIONS — tier hints"
echo "Tier tags are starting points, not verdicts. Confirm each against"
echo "references/known-locations.md before proposing anything."

sub "TIER 1 — regenerable build & dependency cache (cost of deleting = rebuild time)"
probe "$HOME/Library/Developer/Xcode/DerivedData"      "rebuilt on next Xcode build"
probe "$HOME/Library/Developer/Xcode/iOS DeviceSupport" "regenerated when device reconnects"
probe "$HOME/Library/Caches"                            "catch-all app cache"
probe "$HOME/.gradle/caches"                            "re-downloaded on next gradle build"
probe "$HOME/.gradle/wrapper"                           "gradle distributions, re-downloaded"
probe "$HOME/.npm/_cacache"                             "npm cache clean --force"
probe "$HOME/.cache"                                    "generic XDG cache"
probe "$HOME/.pub-cache"                                "dart/flutter packages, re-fetched"
probe "$HOME/.cocoapods/repos"                          "pod repo update re-fetches"
probe "$HOME/.cargo/registry"                           "cargo re-downloads"
probe "$HOME/go/pkg/mod"                                "go mod download re-fetches"
probe "$HOME/Library/Caches/go-build"                   "go build cache"

sub "TIER 2 — safe to delete, but real re-download or behavior cost"
# Docker's disk image location is user-configurable. Read where it ACTUALLY is
# rather than assuming the default — a machine that has already been cleaned up
# once may have moved it to an external drive.
DOCKER_SETTINGS="$HOME/Library/Group Containers/group.com.docker/settings-store.json"
DOCKER_DATA=""
if [[ -f "$DOCKER_SETTINGS" ]]; then
  DOCKER_DATA=$(python3 -c "
import json
try:
    print(json.load(open('$DOCKER_SETTINGS')).get('DataFolder', ''))
except Exception:
    print('')
" 2>/dev/null)
fi
[[ -z "$DOCKER_DATA" ]] && DOCKER_DATA="$HOME/Library/Containers/com.docker.docker/Data/vms/0/data"
if [[ -e "$DOCKER_DATA/Docker.raw" ]]; then
  echo "Docker disk image: $DOCKER_DATA/Docker.raw"
  # Docker.raw is SPARSE. `ls -lh` reports the maximum size Docker is allowed to
  # grow to (often 100-200GB) while du reports the blocks actually consumed.
  # Only du is meaningful. Print both so the difference is visible.
  printf '  du  (real blocks on disk):  %s\n' "$(du -sh "$DOCKER_DATA/Docker.raw" 2>/dev/null | cut -f1)"
  printf '  ls  (apparent size, LIES):  %s\n' "$(ls -lh "$DOCKER_DATA/Docker.raw" 2>/dev/null | awk '{print $5}')"
fi
# What is actually inside the image decides whether purging is cheap or costly.
# 0 images / 0 containers / 0 volumes means the file holds only build cache and
# there is nothing to lose.
if command -v docker >/dev/null 2>&1; then
  sub "docker system df (what is actually inside the image)"
  docker system df 2>/dev/null || echo "  docker daemon not running — start it to see what would be lost"
fi
probe "$HOME/Library/Application Support/Claude/vm_bundles"                        "sandbox VM image, re-downloaded"
probe "$HOME/Library/Android/sdk/ndk"                                              "only needed for native C/C++ Android"
probe "$HOME/Library/Android/sdk/system-images"                                    "emulator images, re-downloadable"
probe "$HOME/.android/avd"                                                         "emulator virtual devices"
probe "$HOME/Library/Application Support/Google/Chrome/OptGuideOnDeviceModel"      "Gemini Nano on-device model"
probe "$HOME/.rustup/toolchains"                                                   "rustup reinstalls"
# Simulator runtimes: the mounted volume under /Library/Developer/CoreSimulator/
# Volumes/* always reads ~98% full — sealed read-only image, that is its normal
# state, not a problem. The real bytes are compressed assets here on the Data
# volume; `du -x` deliberately does not cross into the mount (it would double-
# count). Reclaim ONLY via `xcrun simctl runtime delete`, never rm.
probe "/System/Library/AssetsV2/com_apple_MobileAsset_iOSSimulatorRuntime"         "simulator runtimes; xcrun simctl runtime delete"
if command -v xcrun >/dev/null 2>&1; then
  sub "installed simulator runtimes (reclaim: xcrun simctl runtime delete <id>)"
  xcrun simctl runtime list 2>/dev/null | head -10 || true
fi

sub "TIER 3 — REAL DATA. Never delete on a blanket approval."
probe "$HOME/Library/Application Support/MobileSync/Backup" "iPhone/iPad backups — may be the ONLY copy of a device"
probe "$HOME/Library/Developer/Xcode/Archives" "shipped-build dSYMs; needed to symbolicate crash reports"
probe "$HOME/Library/Application Support/Google/Chrome/Default" "browser profile: history, cookies, passwords"
probe "$HOME/Downloads"
probe "$HOME/Documents"
probe "$HOME/Desktop"
probe "$HOME/Pictures"
probe "$HOME/Movies"
sub "~/Library/Containers — sandboxed app data. Big ones often hold user documents."
children "$HOME/Library/Containers" 8

hr "7. BLIND SPOTS (unreadable without sudo — reported, not touched)"
# This skill deliberately does not use sudo. `sudo rm -rf` with one typo is an
# unbootable machine, and the few GB it buys back are not worth that. Name the
# gaps honestly so the numbers below add up for the user.
for d in /private/var/folders /private/var/log /Library/Caches /System/Volumes/Data/.Spotlight-V100; do
  if [[ -r "$d" ]]; then
    probe "$d" "readable"
  else
    printf '%-8s %s  # NOT READABLE without sudo\n' "?" "$d"
  fi
done
echo
echo "Anything under another user's home, or in system-managed stores, is out of scope."

hr "8. SCAN COMPLETE"
echo "Nothing was deleted. Next: classify findings into tiers and present the"
echo "report. Do not run any rm command until the user approves that tier."
