# GitTickets v2.2.0 + v2.3.0 — report for the ShabuBox team

**Released:** 2026-07-26 · **Tags:** `v2.2.0` → `b2f4d3b`, `v2.3.0` → `09080e2`
**Repo:** https://github.com/awizemann/GitTickets

Two releases since 2.1.0. One closes the dropped-label gap you reported
(**your t-adf29b42**); the other fixes a macOS refresh hole you were almost
certainly hitting without having filed it.

---

## 1. Repin

```swift
.package(url: "https://github.com/awizemann/GitTickets.git", from: "2.3.0")
```

An existing `upToNextMajorVersion` pin from any 2.x **resolves to 2.3.0
automatically** — no manifest change strictly required. Platform floor is
**unchanged** at macOS 14 / iOS 18. No public API was removed or changed in
signature in either release.

---

## 2. Your dropped-label report was correct — and it is fixed

We verified your analysis against the code before acting on it. It holds
exactly as you described:

- The relay lists issues by label: `listLabeledIssues({ label: env.label })`
  → GitHub `?labels=…&state=all`.
- It then matches embedded submission-ID markers against the IDs the client
  sent.
- An issue whose label was never applied fails the **first** narrowing, so it
  can never match the second.
- The relay answers **`200` with zero matches** — not an error.
  `refreshMyIssues()` returned `[]`, and the view rendered its ordinary
  "No reports yet" state.

Your reports still existed on GitHub the whole time. Nothing said they could
not be found. That is fixed in 2.3.0.

### Where we disagreed with your recommendation

You recommended option (a), a readable logger. That is right, and it is what we
built — **but on its own it would not have been enough**, and the reason matters
for your runbook.

`SubmittedIssue.missingLabels` fires at **submission** time. It catches "the App
lost push permission and today's report came back unlabelled". It cannot catch
the three cases that produce *permanently empty*:

1. someone removes the label from existing issues in bulk
2. the relay's configured `label` changes
3. the relay is pointed at a different repo

In all three, nobody files anything new — so `missingLabels` never fires, yet
every past report disappears. Submit-time detection is structurally blind to it.

**2.3.0 therefore also checks at fetch time**, comparing the cached submissions
the SDK asked about against what came back. That catches all three, plus the
original case, and the SDK already held both numbers.

We skipped your option (c), a completion callback: `SubmittedIssue.missingLabels`
is already returned from submit, so a callback would add public API for
information you already have. On option (b), a user-facing warning — the SDK
now hands you the signal and ships a sane default state, but what you show a
user stays your call.

### What to do on your side

**Nothing is required.** `refreshMyIssues()` behaves exactly as before.

Cheapest path, and the one we recommend:

```swift
let config = Configuration(repo: repo, auth: auth, logger: myLogger)
```

A shortfall now logs at two deliberately different severities:

| Situation | Level | Why |
|---|---|---|
| Cached submissions exist, **none** returned | `.warning` | Names the label and the likely causes. Configuration fault. |
| Some returned, some missing | `.info` | A deleted issue does this legitimately — a warning here would cry wolf. |

If you want it in code rather than in logs:

```swift
let refresh = try await GitTickets.refreshMyIssuesDetailed()
if refresh.allMissing {
    // Cached submissions exist but the backend matched none of them.
    // refresh.requestedCount / refresh.unmatchedCount carry the detail.
}
```

**`requestedCount == 0` is deliberately NOT a fault.** A device that has filed
nothing legitimately has nothing to show, and `allMissing` stays `false`. Do not
treat "empty" as "broken" — treat "empty *while* `requestedCount > 0`" as broken.

The built-in view now shows a distinct **"Can't find your reports"** state in
that case. It does not tell the user their reports are gone, because they are
not, and it does not mention labels or permissions, which mean nothing to them —
that detail goes to your logger. If you render your own list, mirror that
distinction.

**Root-cause fix is still yours to make:** grant the GitHub App `Issues: Write`
**and** push access on the target repo. The detection tells you it is happening;
it does not reapply the labels.

---

## 3. v2.2.0 — macOS could not refresh an open window at all

Worth reading even though you did not file it, because it likely explains
behavior you have seen.

Both "My Reports" and Issue Detail used `ScrollView { … }.refreshable { … }`. On
**macOS that installs nothing**: the AppKit hierarchy is byte-identical to
applying no modifier, and the `refresh` environment action is not even
propagated. Only a `List` gets an affordance there.

So on macOS, a newly filed report could not appear in an already-open list, and
a new reply could not appear in an already-open thread. **Closing and reopening
the window was the only refresh mechanism that existed.**

**Correction worth flagging:** if anyone told you to "try pull-to-refresh instead
of reopening the window" on macOS, that advice was wrong — there was no gesture
to find. On **iOS** the same code works correctly and always did (`.refreshable`
does install a `UIRefreshControl` on a plain `ScrollView`), so iOS
pull-to-refresh was never broken and is unchanged.

We measured all of this against the shipped views rather than reasoning about
it; the harnesses are checked in under `Harnesses/RefreshAffordance` and are
re-runnable.

### What 2.2.0 adds

- **A toolbar Refresh control (⌘R)** with an accessibility label. This is the
  only refresh affordance a macOS user can reach directly.
- **Automatic re-fetch when the scene becomes active.** Returning to the window
  picks up new issues and replies with no user action. This is the one that
  most likely matters to you day to day.
- **`MyIssuesPolicy.pollInterval` now works.** It had been public since Phase 2
  but nothing read it, so no auto-refresh existed under any configuration.

```swift
MyIssuesPolicy(pollInterval: 0)   // default — off
```

**Leave it at `0` unless you specifically need live updates.** Polling costs one
request per open screen per interval against your relay and GitHub's rate
limits. Scene reactivation covers most of what polling would buy you, for free.
A negative value is treated as `0` rather than spinning.

2.3.0 additionally stops a refresh from blanking the list to a spinner — with
three refresh triggers now landing in the same place, that would have flickered
on an interval with polling on.

---

## 4. Known limits

- **Fetch-time detection is a signal, not a repair.** It tells you the labels
  are missing; you still have to fix the App permissions and, for issues already
  filed unlabelled, reapply the label or re-submit.
- **A partial shortfall is ambiguous by design.** One missing report looks
  identical to one deleted issue, so it logs at `.info` and does not trigger the
  distinct UI state. Only a total miss does.
- **The affordance checks in our harnesses verify the mechanism is installed,
  not that a human gesture invokes it.** Gesture-level testing needs input
  injection we do not currently run.

---

## 5. Verification behind both releases

| | v2.2.0 | v2.3.0 |
|---|---|---|
| Commit | `b2f4d3b` | `09080e2` |
| Local | 0 warnings, 301 tests / 0 failures | 0 warnings, 306 tests / 0 failures |
| CI macOS | 301 exec / 6 skipped / 0 fail | 306 exec / 6 skipped / 0 fail |
| CI iOS | 289 exec / 30 skipped / 0 fail | 294 exec / 30 skipped / 0 fail |
| Tag proved | resolved `from: "2.2.0"` off the public remote, built **and ran** | resolved `from: "2.3.0"`, built **and ran** |

Both followed the same order: merge → push → wait for CI green → tag → prove the
tag from the public remote with a cold SPM cache. The 2.3.0 proof asserts the
exact semantics above — that `allMissing` is true for cached-submissions-with-
zero-matches, false for a device that has filed nothing, and false for a partial
shortfall.

---

## Questions

Open an issue on the GitTickets repo, or reply through the usual channel.
