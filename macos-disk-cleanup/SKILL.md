---
name: macos-disk-cleanup
description: Audit macOS disk usage, find what is actually eating space, sort every finding into a safety tier, and reclaim space only after the user approves each tier. Use this whenever the user mentions a full or nearly-full disk, "free up space", "what's taking up space", "why is my Mac's storage full", a startup-disk-full warning, low disk space, or clearing caches — and also when they ask about one specific space hog like Docker.raw, Xcode DerivedData, node_modules, gradle caches, or ~/Library. Trigger it even when they only ask the diagnostic question ("why is my disk full?") without asking for a cleanup, since the audit is the same work either way.
---

# macOS Disk Cleanup

Find the space, classify it by what deleting it would *cost*, propose, and only
then — with approval — reclaim it.

## The one rule

**You do not delete anything the user has not approved.** Not "obvious" caches,
not "it's just a build artifact", not even when the user opened with "clean up
my disk." A blanket "clean my disk" is not approval, because nobody can approve
a deletion they haven't seen yet. Scan first, show them, *then* ask.

This isn't ceremony. Disk cleanup is the one class of task where being fast and
being wrong are the same action, and there is no undo. A rebuild you triggered
unnecessarily costs ten minutes. A deleted archive costs a shipped app's crash
reports forever. The asymmetry is the whole reason this skill exists.

## Workflow

1. **Scan** — run the bundled script. Read-only.
2. **Classify** — every finding lands in exactly one tier.
3. **Report** — one table, ranked by size, with a running total.
4. **Ask** — which tiers to execute. Wait for a real answer.
5. **Execute** — only the approved tiers, only the exact paths you listed.
6. **Verify** — re-measure and show before/after.

### 1. Scan

```bash
bash <skill-path>/scripts/scan_disk.sh
```

Takes 1-3 minutes. It walks every inode; there is no faster way. Run it **once**
and read the entire output before reasoning. The temptation to fire off six
rounds of ad-hoc `du` calls is strong and it wastes minutes — the script already
covers baseline, backup status, home (including dotfiles), `~/Library`, system
directories, the known-location catalog, Docker internals, and the unreadable
blind spots.

Only reach for a manual `du` when the scan surfaces something it doesn't have a
probe for — a large unrecognized directory you need to break down further.

### 2. Classify — the three tiers

The tier is not about how big something is. It's about **what it costs you to be
wrong about it.**

**Tier 1 — Regenerable.** The machine rebuilds it, unprompted, from things it
still has. Deleting is free except for time. Build outputs, dependency caches,
compiler caches. `DerivedData`, `.gradle/caches`, `~/Library/Caches`, `node_modules`.

**Tier 2 — Replaceable.** Recoverable, but it costs a download, a reinstall, or
a changed behavior the user might notice. Docker disk images, on-device ML
models, SDK components, VM bundles, emulator images. Say what the cost is so the
user can price it — "Docker's next build will be slow" is information they need.

**Tier 3 — Irreplaceable.** Gone means gone. User documents, app container data,
browser profiles, shipped-build archives, anything in `~/Documents`, `~/Desktop`,
`~/Downloads`, `~/Pictures`.

**Tier 3 is never covered by a blanket approval.** If the user says "yes, do tier
1 and 2", that says nothing about tier 3. Each Tier 3 item gets named
individually, with what would be lost, and confirmed on its own. Usually the
right move is to leave Tier 3 alone entirely and let the user decide in their own
time — you are not on the hook for reaching a number.

If you genuinely can't tell which tier something belongs in, it's Tier 3. The
uncertainty *is* the classification.

Consult `references/known-locations.md` for the catalog: what each known path is,
its tier, the correct way to reclaim it, and the per-tool traps.

### 3. Report

Lead with the number the user cares about, then the table:

```
Disk: 191GB used / 14GB free (94%)

## Tier 1 — safe, regenerates itself
| Path | Size | What deleting it costs |
|---|---|---|
| ~/Library/Developer/Xcode/DerivedData | 31G | next Xcode build is slow |
| ~/.gradle/caches | 9.0G | next gradle build re-downloads deps |
| ...  | | |
| **Tier 1 total** | **69G** | |

## Tier 2 — safe, but costs a re-download
...

## Tier 3 — real data. Not touching without a per-item OK.
| ~/Library/Containers/com.acme.app | 5.7G | app's saved documents — need you to look |
```

Give a running total per tier so the user can stop as soon as they have enough
headroom. Reclaiming every last gigabyte is not the goal; getting them out of the
danger zone is.

Also report what you **couldn't** see. The scan skips anything needing `sudo`, so
the tier totals won't reconcile with `df`. Say so plainly rather than letting the
user wonder where the missing gigabytes went.

### 4. Ask

Use the question tool. One question, options per tier, with the totals in the
labels so the choice is legible. Then wait. "Proceeding with tier 1 since it's
safe" is exactly the failure this skill is built to prevent.

If the backup check in the scan came back empty, say so **here**, before they
choose — not in a footnote afterwards. Someone with no Time Machine backup should
know that before they weigh anything in Tier 3.

### 5. Execute

Only the approved tiers. Only the exact paths from the report — no globs that
could match more than what you showed, no "while I'm in there."

Some reclaims are not `rm` at all, and using `rm` instead will either fail or
corrupt something. `references/known-locations.md` gives the correct mechanism per
tool. Docker in particular is a trap; read that section before touching it.

### 6. Verify

Re-run `df -h /System/Volumes/Data` and show before/after. Then reconcile: if
freed space doesn't match what you deleted, **say so and investigate.** A number
that doesn't add up means something else changed, and the user needs to know
whether that something was you.

## Traps

These cost real time to discover. Believe them.

**`du -sh ~/*` skips every dotfile directory.** On a developer machine that is
where real space hides — `~/.gradle`, `~/.cache`, `~/.pub-cache`, `~/.npm` (once
~19GB invisible on this pattern alone). The scan script enables `dotglob` so its
globs physically can't repeat the mistake; if you write a manual `du`, glob
`~/.[!.]*` too.

**A du-vs-df gap has three stacked causes — don't stop at the first.** When a
user's hand-added `du` total falls short of `df`, the causes stack: (1) the
dotfile glob miss above, (2) usually the *biggest* one — they measured `~` but
`df` measures the whole volume, and `/Applications`, `/Library`, `/System`,
`/opt` routinely hold 40GB+ outside home, (3) a few GB genuinely unreadable
without sudo. Reconcile all three or the user stays confused. And if your line
items don't sum to the volume total, say so plainly — APFS clones and firmlinks
distort sums — never invent a tidy explanation for a number you didn't verify.

**iOS Simulator runtime volumes are ~98% full by design.** `df` shows a mount
like `/Library/Developer/CoreSimulator/Volumes/iOS_...` at 98% — it is a sealed,
read-only disk image sized to fit its contents. Nothing is wrong, nothing there
can be `rm`'d, and any tool calling it a "full disk" is misreading it. The real
bytes live compressed under `/System/Library/AssetsV2/` on the Data volume
(a "17G" volume may cost only ~8G there). `du -x` won't cross into the mount —
correct, counting it would double-count — but that means AssetsV2 must be probed
separately or those GB silently vanish from your report. Reclaim only via
`xcrun simctl runtime delete`, never `rm`.

**`df -h` speaks GiB; `diskutil` and Finder speak GB.** `117Gi` and `125 GB`
are the same quantity. Convert before comparing, or you manufacture a phantom
8GB discrepancy.

**`ls -lh` lies about sparse files.** `Docker.raw` will report 228G in `ls` and
7.9M in `du`, because `ls` prints the size it's *allowed to grow to*. Finder lies
the same way. Only `du` and `df` describe reality. Never report an `ls` size as
disk usage, and reassure the user when they see the scary Finder number.

**Always pass `-x` to `du`.** Without it you'll walk into `/Volumes` and count an
external drive as internal usage, and every number after that is wrong.

**Check what's inside a store before proposing you nuke it.** `docker system df`
tells you whether that 21GB image holds irreplaceable volumes or just build
cache. Same instinct everywhere: measure the contents, not just the container.

**`~/Library/Containers/<app-id>` is app data, not cache.** The name looks like
infrastructure. The contents are often the user's documents.

**Xcode `Archives` are not build artifacts.** They carry the dSYMs that
symbolicate crash reports from shipped builds. Deleting them is irreversible in
the way that matters.

## Match the scope of the question

"Why is my disk full?" gets the scan and the report — then you stop. Don't push
toward deletion nobody asked for, and don't stage ready-to-run `rm` commands
"for convenience": an unrequested deletion menu one "yes" away from executing is
how a diagnostic question turns into an accident. The report is a complete
answer.

A narrow question gets a narrow answer. "What is this Docker.raw file?" is about
one artifact — measure it, explain it, resolve it. Don't bolt a full-disk audit
onto the back of it; offer one in a single line ("want the full picture?") and
let the user opt in. The full workflow is for when cleanup is actually the task.

## References

- `references/known-locations.md` — catalog of macOS space hogs: tier, correct
  reclaim mechanism, per-tool traps. Read it during classification, and always
  before executing anything involving Docker, Xcode, or Homebrew.
