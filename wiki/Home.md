---
title: Home
type: note
permalink: gittickets-wiki/home
---

# GitTickets Wiki

Long-form reference for **GitTickets**, a Swift package (macOS 13+ / iOS 16+) that gives any app a drop-in "Report an Issue / Feature Request" surface backed by the app's own GitHub repository.

## Status

**v1.0.0** shipped (tagged + on GitHub). **v1.1.0** is release-prepped — the
SDK now builds in the Swift 6 language mode (minimum toolchain Swift 6.0 /
Xcode 16+; runtime floor unchanged at macOS 13+ / iOS 16+) and the relay
templates are deployed-and-tested. See [`CHANGELOG.md`](../CHANGELOG.md) for
the full ship list. The v1.1.0 tag-and-push is held pending validation in
Memophant (the shipping host app, mid Swift-6 migration).

## What GitTickets is

A Sparkle-style add-the-package-and-go bug-report SDK for Apple platforms. The adopter drops the package in, points it at a relay URL (or an OAuth client ID), and adds `GitTicketsCommands { … }` to their SwiftUI `Commands` builder — or `GitTicketsMenuItemFactory.makeReportIssueItem()` in AppKit. End-users get a native form, screenshots, diagnostics, privacy-banner, and submit. The issue lands directly in the app's GitHub repo.

**Phase 2 surface** also ships in v1.0 — `GitTicketsMyIssuesView` lets users browse their past submissions and see maintainer replies as a thread, in-app. Unread-reply badges, pull-to-refresh, comment markdown rendering, and an "Open on GitHub" affordance per row.

## Adopter docs

The end-user-facing reference docs that travel with the SDK live under
[`docs/`](../docs/). They're authoritative for adopters integrating the
package:

- [`docs/getting-started.md`](../docs/getting-started.md) — install, configure, wire the UI.
- [`docs/architecture.md`](../docs/architecture.md) — client SDK + dual auth, data flow, ASCII map.
- [`docs/threat-model.md`](../docs/threat-model.md) — what the relay protects against (and doesn't).
- [`docs/relay-deployment.md`](../docs/relay-deployment.md) — Vercel + Cloudflare walkthrough.
- [`docs/device-flow.md`](../docs/device-flow.md) — opt-in OAuth path.
- [`docs/theming.md`](../docs/theming.md) — `GitTicketsTheme` fields + examples.
- [`docs/diagnostics.md`](../docs/diagnostics.md) — what's collected, redaction, opt-outs.
- [`docs/privacy.md`](../docs/privacy.md) — privacy manifest + adopter guidance.

## Contributor wiki

This wiki is contributor-facing — the durable-decisions history and the
"things to check on every PR touching X" cheat sheet. Adopter integration
walkthroughs belong in [`docs/`](../docs/).

- [Architecture](Architecture) — internal-facing version of the data flow + module layout.
- [Threat Model](Threat-Model) — what the relay protects against and what it doesn't.
- [Relay Deployment](Relay-Deployment) — operations runbook.
- [Device Flow](Device-Flow) — state-machine notes for the OAuth path.
- [Diagnostics & Screenshots](Diagnostics-and-Screenshots) — collection + redaction internals.
- [Patterns & Gotchas](Patterns-and-Gotchas) — the durable-rules index that pairs with `.memory/footguns/`.
- [Build Sequence](Build-Sequence) — the 20-PR build plan, now a shipped record.
- [Wiki Maintenance](Wiki-Maintenance) — how this wiki is edited and kept safe.

## Design

Two visual handoffs from Claude Design are committed under
[`design/`](../design/). The package ships the generic / brand-neutral
version (system blue accent, theme-agnostic surfaces). Hosts override the
accent via `Configuration.theme`:

- [`design/design_handoff_gittickets_views_generic/`](../design/design_handoff_gittickets_views_generic/) — the SwiftUI redesign of `GitTicketsView` + `IssueDetailView` + `GitTicketsMyIssuesView` shipped in v1.0, with an HTML reference render.

## Roadmap (post-v1.0)

- **v1.1** — native rendering of `.github/ISSUE_TEMPLATE/*.yml` Issue Forms.
- **v1.x** — relay-side telemetry opt-in surface (see TASKS.md stretch item).
- **v1.x** — fix iOS-Simulator XCTest Keychain entitlement so SPM-only
  tests run on Sim without the host-app workaround. See
  [Patterns & Gotchas](Patterns-and-Gotchas).

---
_Last updated: 2026-06-06 — v1.0 shipped, wiki refreshed_
