---
title: Reply alert: checkForReplies throttle design
type: note
permalink: gittickets/architecture/reply-alert-checkforreplies-throttle-design
tags: [reply-alert, v2.6.0, throttle]
source_paths: [Sources/GitTickets/PublicAPI/GitTickets.swift, Sources/GitTickets/Storage/SubmissionCache.swift, Sources/GitTickets/Networking/HTTPClient.swift]
source_paths_inferred: false
source_sha: 1a740743fb670bb4e5e2c33812cf95c768e52639
created: 2026-10-05
updated: 2026-10-05
---

Shipped in v2.6.0 (2026-10-05). Design doc: documents/designs/2026-10-05-reply-alert-design.md. Went through two adversarial audits; the notes below are the non-obvious decisions they forced.

## Observations
- [decision] GitTickets.unreadReplyCount reads the cache with one SUM query; checkForReplies() refreshes at most every 15 min, coalesces concurrent calls into one Task, and runs with HTTPClient.attemptLimit=1 (TaskLocal) so 5xx isn't retried #reply-alert
- [decision] The 15-min window is persisted in SubmissionCache's meta table (key reply_check.last_check_at), NOT UserDefaults — UserDefaults is a required-reason API and would force a privacy-manifest change #privacy #reply-alert
- [gotcha] Only pre-connection URLErrors (offline, DNS, cannotConnect, TLS) and deviceFlowNotAuthorized leave the window open; timedOut/networkConnectionLost/cancelled count because the relay probably already counted the request #reply-alert
- [gotcha] The meta table is created best-effort (try?) because on an upgraded 2.5.0 DB it is the first real write at open; a hard failure there would lose the whole cache for the run #storage
- [fact] A failed check clears the stored window only if it still holds the value that check claimed (compare-and-delete), so it can't wipe a newer My Reports refresh stamp #reply-alert

## Relations
- relates_to [[Private repos show no GitHub links in My Reports]]
