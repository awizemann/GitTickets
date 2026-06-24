---
title: PR 15 Complete — My Issues (Phase 2)
type: note
permalink: gittickets/progress/pr-15-complete-my-issues-phase-2
tags:
- progress
- pr-15
- phase-2
- my-issues
- swiftui
source_sha: 7a91c04dc0c63debdc49916f60c1b50cfd90c3f6
reviewed: 2026-06-24
reviewed_by: human
---

Phase 2's full UI + fetch surface landed in one PR. Both submitters now implement all three fetch methods; both relay templates have a `/comments` endpoint at parity; the SwiftUI tier ships a list view, a detail view, and a markdown comment renderer. Manual refresh in v1 as the task spec called for.

## Observations

- [verified] 209/209 Swift green (was 203 — +6 new). 37/37 Vercel + 32/32 Cloudflare green. iOS Sim build clean. #verification
- [shipped-sdk] `Sources/GitTickets/PublicAPI/Models.swift` — new public `IssueComment(id, author, body, createdAt)` value type, `Sendable + Hashable + Identifiable` so SwiftUI `ForEach` diffs without an `id:` key path. #pr-15
- [shipped-sdk] `IssueSubmitter.fetchComments(issueNumber:deviceID:)` added with throwing default — same opt-in shape as `fetchMyIssues`/`fetchReplies`. Both production submitters override. #pr-15
- [shipped-sdk] `RelaySubmitter.fetchComments` posts to `/comments` via the existing signed-POST path, projects `[CommentsItem]` → `[IssueComment]` via `parseISO8601` with malformed-date `compactMap` skip. #pr-15
- [shipped-sdk] `DeviceFlowSubmitter.fetchMyIssues` — cache-driven. For each known submissionID, GET `/repos/:owner/:name/issues/:n` and rebuild a fresh `SubmissionRecord` (title/comments/updated_at from GitHub, `readReplyCount` preserved from the cached row). Wholesale rebuild rather than mutation because `SubmissionRecord.title` is `let` and I wanted to avoid changing the public surface just for one update path. Per-record failures log + return the cached projection so the list still renders. #pr-15
- [shipped-sdk] `DeviceFlowSubmitter.fetchComments` GETs `/repos/:owner/:name/issues/:n/comments`, decodes into a private `GitHubComment` wire type, maps to `IssueComment`. 401 wipes the dead token via the same `validateIssueResponse` path the submit-side uses — `.deviceFlowNotAuthorized` so the form's auth sheet re-presents on the next attempt. #pr-15
- [shipped-sdk] `GitTickets.cachedSubmissions()`, `refreshMyIssues()`, `fetchComments(issueNumber:)`, `markRepliesRead(submissionID:count:)` — public static methods so adopters who roll their own My Issues UI don't have to reach into internals. Backs the SwiftUI views' default behavior + serves as the documented programmatic API for v1.x. #api
- [shipped-ui] `Sources/GitTickets/UI/SwiftUI/GitTicketsMyIssuesView.swift` — public list. Cache-first render on `.task` for instant first paint; auto-refresh once on appear to sync server state without polling. Unread badge is a capsule with the accent color. `NavigationLink(value:)` + `navigationDestination(for: SubmittedIssue.self)` so iOS NavigationStack and macOS NavigationSplitView both work via the value-based push. Empty + unconfigured placeholder states. ToolbarItem refresh button with in-flight `ProgressView`. #pr-15
- [shipped-ui] `Sources/GitTickets/UI/SwiftUI/IssueDetailView.swift` — public detail. Title + filed-date + reply-count header; "Open on GitHub" via SwiftUI `openURL` env; comments load via the injected `fetcher` closure (defaults to `GitTickets.fetchComments`). State machine `idle/loading/loaded/failed` so the UI surfaces network failures inline rather than crashing. Marks all replies read on `.task` — the badge clears immediately, before the network load even completes, so the list updates feel responsive. #pr-15
- [shipped-ui] `Sources/GitTickets/UI/SwiftUI/MarkdownCommentView.swift` — public single-comment renderer. `AttributedString(markdown:)` with `interpretedSyntax: .inlineOnlyPreservingWhitespace` — chosen deliberately so a stray `# heading` line in a reply doesn't eat the whole comment as a block heading. Plain-text fallback when the body fails to parse. Author header (`@author`), relative timestamp, body. Theme honors `bodyFont` + `cornerRadius`. #pr-15
- [shipped-relay] Vercel `relay/vercel/api/comments.ts` + Cloudflare `relay/cloudflare/src/handlers/comments.ts`. Same wire contract as Vercel's other endpoints — HMAC auth, rate-limit, GitHub App installation token. New `listComments()` helper in both `_lib/github.ts` paging 5×100=500 max. Both templates: 404 from GitHub maps to `200 { comments: [] }` (issue gone or invisible to the installation — SDK renders "no replies yet" rather than a hard error which would confuse the user). #pr-15
- [shipped-relay] `CommentsRequestSchema` + `CURRENT_COMMENTS_SCHEMA_VERSION = 1` added to both zod payload modules. `vercel.json` rewrites + worker.ts router both updated to handle `/comments` and `/api/comments`. `relay/shared/payload-schema.md` updated with the `/comments` section so future relay implementations have the contract. #wire-contract
- [decision] Manual refresh only in v1 (`MyIssuesPolicy.pollInterval = 0` default). Auto-poll would burn relay rate budget on every-30-seconds checks for users who aren't actively looking at the list. The auto-refresh-once-on-appear inside `GitTicketsMyIssuesView` gives the "fresh on open" UX without the cost of background polling. Adopters can crank `pollInterval` if they need it. #scope
- [decision] Device Flow `fetchMyIssues` walks the cache rather than hitting GitHub Search with `author:@me+label:gittickets`. Cache-walk is cheaper (one GET per cached row vs. one Search + N GETs), works offline as a graceful degradation (per-record failures fall back to cached projection), and avoids the GitHub Search rate-limit tier which is much tighter than the per-repo Issues tier. Tradeoff: an issue filed from a different install of the same app won't appear in the My Issues list until that install's cache is hit somehow — accepted because Device Flow's model is "this user filed this issue from this device." #decision
- [shape-match-avoided] Every new fetch method has a real implementation on BOTH submitters and is dispatched from a public `GitTickets.*` static method. No "infrastructure built but public-API never reached it" pattern. The tests (`test_fetchCommentsRoundTrips` on both submitters + the existing `test_deviceFlowDispatchReachesSubmitter`) lock the dispatch. #pattern
- [defer] Snapshot tests for the My Issues views — same reasoning as PR 12 had for the form. The layouts will iterate when Memophant validates them; locking baselines now would just churn. PR 19's sample-app validation pass is the natural place. #scope
- [defer] Comment caching in SubmissionCache — punted. Comments are fetched fresh on every IssueDetailView open. Caching them would require a new SQLite table + invalidation strategy + the merge-with-server logic, none of which is essential for v1's manual-refresh UX. Open issue for v1.x if the relay round-trip becomes a UX bottleneck. #scope
- [defer] Memophant integration of the new views — landing in a follow-up. Memophant currently presents the report form via a Window scene; adding a "My Issues" Window scene + menu entry is two more wireframe lines. Hold for user validation. #next
- [defer] iOS Sim Keychain entitlement still on TASKS.md as a separate item — unaffected. #unchanged

## Relations

- follows [[PR 16 Complete — Theming Polish]]
- follows [[Phase 1 Complete — PR 17 / 18 / 19 / 20 Polish + Release]]
- closes "PR 15 — My Issues" on TASKS.md
- closes Phase 2 of the build-sequence plan
- enables Memophant My Issues integration (next session)
