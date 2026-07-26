# Releasing GitTickets

The order below is not stylistic. Every step exists because skipping it broke a
real release. Follow it top to bottom.

**The rule everything else serves: a tag annotation, a CHANGELOG entry, and a
README claim may only state things that have been measured.** Not intended, not
expected — measured, in this release, on this commit.

---

## Why the order is what it is

v1.1.0 was announced in the README and the CHANGELOG but **never tagged**. The
docs said it existed. SPM disagreed: `from: "1.1.0"` failed to resolve outright,
and the first adopter to hit it had to pin `1.0.0` instead. Nothing in the repo
caught it, because nothing ever tried to resolve the version the docs promised.

So: **push first, wait for CI, tag last, then prove the tag by resolving it.**
Tagging before CI means the annotation records an intention. Tagging without
proving means the docs can promise a version that does not resolve.

---

## 1. Pre-flight — before you touch a version number

- [ ] **Every user-visible change has a doc.** ⟵ *the one most often skipped*
- [ ] Working tree clean apart from the Memophant-managed tiers (`.memory/`,
      `TASKS.md`, `tasks/`, `wiki/`, `design/`, `documents/`). Never commit those.
- [ ] `swift build` — **0 warnings**.
- [ ] `swift test` — green. Record the count; it goes in the annotation.
- [ ] `xcodebuild -scheme GitTickets -destination 'generic/platform=iOS Simulator' build`
      — **BUILD SUCCEEDED**.

### The documentation guardrail, in full

Before tagging, for each entry in the release's CHANGELOG section, ask:

> **Can an adopter discover and use this without reading the CHANGELOG?**

If the answer is no, the release is not ready. A CHANGELOG entry is a record of
what changed, not documentation of how to use it. Specifically:

| The change | Needs |
|---|---|
| New public API | A doc comment **and** a mention in the relevant `docs/*.md` |
| New user-visible behavior (a control, a state, a default) | A section in `docs/` describing when a user sees it |
| A changed default | An explicit "how to opt out" line in the CHANGELOG |
| A fixed bug that adopters worked around | A note telling them they can drop the workaround |

This exists because v2.2.0 and v2.3.0 both shipped user-visible behavior — a
toolbar Refresh control, scene reactivation, `pollInterval` going from dead to
live, and the dropped-label signal — with **no documentation outside the
CHANGELOG**. It had to be backfilled afterwards.

Related trap: a doc comment that describes an affordance nobody wired. Three
have shipped in this repo — `pollInterval` promising a ⌘R shortcut that did not
exist, `GitTicketsMyIssuesView`'s header claiming a macOS gesture that does not
exist, and a screenshot doc comment implying the built-in form could add one.
**If a doc comment names a behavior, exercise that behavior before you tag.**

---

## 2. Version metadata

- [ ] `Sources/GitTickets/Networking/UserAgent.swift` — bump `sdkVersion` **and**
      the example in its doc comment. They drift apart easily.
- [ ] `CHANGELOG.md` — promote `[Unreleased]` to `## [X.Y.Z] — YYYY-MM-DD`, and
      leave a fresh empty `[Unreleased]` at the top.
- [ ] `CHANGELOG.md` — add the `[X.Y.Z]:` link reference at the bottom and
      repoint `[Unreleased]:` at `compare/vX.Y.Z...HEAD`.
- [ ] `README.md` — the Status section, the `from: "X.Y.Z"` pin, and the test
      count.
- [ ] `docs/getting-started.md` — the install snippet pin.

Grep for the previous version afterwards. It hides in doc comments and install
snippets:

```bash
grep -rn "2\.2\.0" README.md docs/ Sources/ CHANGELOG.md
```

---

## 3. Merge, push, wait

```bash
git checkout main
git merge --no-ff feature/your-branch
git push origin main
```

**Verify the push actually moved `main`.** A commit made on a detached HEAD is
invisible to `git push`, which reports `Everything up-to-date` and exits 0:

```bash
git rev-parse HEAD main origin/main   # all three must match
```

This has happened. `git push` succeeding is not evidence your commit shipped.

Then wait for CI to go green:

```bash
gh run list --branch main --limit 1
gh run watch <run-id> --exit-status
```

- Both jobs — **macOS and iOS** — must be green. Capture **both** test counts;
  they differ (macOS runs the AppKit and snapshot suites).
- The Node 20 deprecation annotation on `actions/cache@v4` and
  `actions/checkout@v4` is expected infrastructure noise, not a failure.

**Do not tag until this is green.**

---

## 4. Tag

```bash
git tag -a vX.Y.Z <commit> -F -
git push origin vX.Y.Z
```

The annotation must state, and only state, what was measured:

- what changed, and what it means for an adopter
- whether any public API was removed or changed in signature
- whether the platform floor moved
- whether an existing `upToNextMajor` pin resolves to it automatically
- local `swift build` warnings and `swift test` count
- the CI run number, the commit, and **both** job counts

---

## 5. Prove the tag

Non-negotiable. This is the single check that would have caught v1.1.0.

In a scratch directory, with a **cold** SPM cache, against the **public** remote:

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/awizemann/GitTickets.git", from: "X.Y.Z")
]
```

```bash
swift build --cache-path .spmcache --scratch-path .build
grep -E '"revision"|"version"' Package.resolved   # must match the tagged commit
./.build/debug/YourProof                          # build AND run
```

Assert against the published artifact, not your working tree:

- the previous major/minor's call sites still compile (source compatibility)
- the new release's headline behavior is actually present
- defaults that were promised to be unchanged really are

A build alone is weak. Run it, and make it assert.

---

## 6. Publish the GitHub Release

Tags alone are invisible on the Releases page, and the CHANGELOG links point
there. Reuse the annotation you already wrote:

```bash
git for-each-ref refs/tags/vX.Y.Z --format='%(contents)' | tail -n +2 > /tmp/notes.md
gh release create vX.Y.Z --title "GitTickets X.Y.Z" --notes-file /tmp/notes.md --verify-tag --latest
```

---

## 7. Close the loop

- [ ] `gh release list` shows the new release as **Latest**.
- [ ] The README no longer claims a version that does not exist.
- [ ] Adopters who asked for something in this release have been told.

**Do not leave a release half-finished across sessions.** Between pushing `main`
and creating the tag, the README on the public repo claims a release that does
not resolve — the exact v1.1.0 failure. Close that window in the same sitting.

---

## Fixing a bad tag

**Annotation wrong, commit right.** Safe, and the common case:

```bash
git tag -f -a vX.Y.Z <same-commit> -F -
git push --force origin vX.Y.Z
git ls-remote --tags origin | grep vX.Y.Z   # vX.Y.Z^{} must be unchanged
```

The tag object changes; the commit it points at must not. SPM resolves version →
commit, so anyone already pinned gets byte-identical code. Re-run the proof
anyway. Caveat: anyone who already fetched keeps the old annotation until
`git fetch --tags --force`, so this is only acceptable soon after tagging.

**Tag missing entirely** (the v1.1.0 case): tag the commit that shipped it,
push, and say so plainly — v1.1.0 was backfilled on 2026-07-25, long after the
docs announced it.

**Commit wrong.** Do not move the tag. Ship the next patch version. A published
tag pointing at different code breaks everyone who resolved it.

---

## Notes

- **The relay templates version independently** of the SDK
  (`relay-vercel-vX.Y.Z`, `relay-cloudflare-vX.Y.Z`). An SDK release does not
  imply a relay release, and the CHANGELOG says so at the top.
- **A fresh worktree's first `swift test` reports 6 failures.** Snapshot
  baselines are deliberately untracked (`**/__Snapshots__/*` in `.gitignore`,
  because rendered PNG bytes depend on the recording machine), and
  `swift-snapshot-testing` reports a first recording as a failure. Run it again
  before believing it. The same 6 are what CI reports as *skipped* on macOS —
  `SnapshotTests` skips itself when `CI` is set. Two sessions have lost time to
  this, one misdiagnosing it as Keychain noise.
- **Harnesses live in `Harnesses/`** and are not part of the shipped package. If
  a release makes a platform-behavior claim, re-run the relevant harness rather
  than restating the claim from memory.
