# Design: telling the host app when a maintainer replies (2026-10-05)

Status: proposal — awaiting Alan's decision. Task t-38342558.

## What already works
- Unread state is local and offline: `SubmissionCache` stores reply_count + read_reply_count (`Storage/SubmissionCache.swift:94-108`); unread = `max(0, replyCount - readReplyCount)` (`Storage/SubmissionRecord.swift:45`), exposed as `SubmittedIssue.unreadReplyCount` (`PublicAPI/Models.swift:166`).
- `cachedSubmissions()` is SQLite-only (`PublicAPI/GitTickets.swift:79-85`); `refreshMyIssues()` updates reply counts and keeps read counts.
- `markRepliesRead` runs when Issue Detail opens (`UI/SwiftUI/IssueDetailView.swift:145`).
- `GitTicketsMyIssuesCommands` already takes a `title:`, so a host can show "My Reports (2)".

A host can already do it today:
```swift
func unreadTotal() -> Int { GitTickets.cachedSubmissions().reduce(0) { $0 + $1.unreadReplyCount } }
badge = unreadTotal()                                            // instant, offline
_ = try? await GitTickets.refreshMyIssues(); badge = unreadTotal() // network, on launch
```

## Real gaps
1. Not documented anywhere — hosts won't find it.
2. **Checking can block filing reports.** `/my-issues`, `/comments` and `/report` share one per-device budget (10/hour default, `relay/cloudflare/src/lib/env.ts:60`) and a 30/hour per-IP budget (`lib/rateLimit.ts`). A host that refreshes on every app activation (many times an hour on macOS) burns the budget and the user's next bug report gets a 429. Verified in code.
3. No change signal: a host badge only clears if the host re-reads the cache (sheet `onDismiss` covers sheets, not long-lived windows).
4. Relay cost per check: 1–5 pages of labelled issues + 1 comments call per issue with replies, all on the app's shared GitHub App quota.

## Options (smallest → largest)
- **A. Document the recipe** with a "launch + at most every ~15 min; never poll" warning. No API. Every host re-implements the throttle.
- **B. Two static members (recommended):**
  - `GitTickets.unreadReplyCount: Int` — cache only, synchronous.
  - `GitTickets.checkForReplies() async -> Int` — refresh, throttled by an internal minimum interval (~15 min), no-op when nothing has been filed or My Issues is disabled, errors fall back to the cached total.
- **C. B + a change notification** (`gitTicketsUnreadRepliesDidChange`) and an optional badge on `GitTicketsMyIssuesCommands`. More API; wait for a host to ask.
- **Not recommended: local user notifications** — permission prompt, only fire while the app is running, and a badge does the same job while it is.

## Recommendation
B, documented with A's recipe. Two public members, no new types. Separately, consider giving `/my-issues` + `/comments` their own rate-limit bucket so reading replies can never block filing a report.

## Related bug found while investigating (verified)
`latestComment` in both relays (`relay/cloudflare/src/lib/github.ts:170`, `relay/vercel/api/_lib/github.ts:187`) asks GitHub's per-issue comments endpoint for `sort=created&direction=desc&per_page=1`. That endpoint ignores sort/direction, so it returns the **oldest** reply. Result: "last reply …" in Issue Detail and the My Reports sort order use the first reply's date, not the latest. Fix: request `per_page=1&page=<comment count>` (the count is already on the issue object at the call site, `handlers/myIssues.ts:92`).
