---
id: t-034fdaa2
title: 2.6.0: hide GitHub links in My Reports for private repos
status: done
added: 2026-10-05
priority: high
---

## Description

ScarfRack (private repo, relay mode) asked for replies in-app only. In My Reports a GitHub link on a private repo is a 404/login wall for reporters. Alan's ruling (2026-10-05): no GitHub link whenever repo.visibility == .private, regardless of auth mode.

Sites: IssueDetailView header "Open on GitHub" (IssueDetailView.swift ~185); IssueStateCard "Open on GitHub" button + error copy "Replies live on GitHub" (IssueDetailComponents.swift ~214/247); DiagnosticsAffordance "View on GitHub" (IssueDetailComponents.swift ~80) — that one is plain text styled like a link and does nothing on ANY repo.

Reuse the form's existing rule (GitTicketsView.swift isPublicRepo: configuration?.repo.visibility != .private; nil config = public) as one shared internal helper rather than a second copy.

## Plan

1. One internal helper for "reporters can open this repo on GitHub"; GitTicketsView.isPublicRepo uses it too.
2. Header link + state-card button hidden when private; error copy neutral when private.
3. Diagnostics line: drop the fake "View on GitHub" text on every repo (it is not a link).
4. Tests: unit test of helper (public/private/nil config); view-level tests for which elements show; snapshot tests of IssueStateCard public vs private (local-only suite).
5. swift build + swift test green.

## Artifacts



