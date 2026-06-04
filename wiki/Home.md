---
title: Home
type: note
permalink: gittickets-wiki/home
---

# GitTickets Wiki

Long-form reference for **GitTickets**, a Swift package (macOS 13+ / iOS 16+) that gives any app a drop-in "Report an Issue / Feature Request" surface backed by the app's own GitHub repository.

## What GitTickets is

A Sparkle-style add-the-package-and-go bug-report SDK for Apple platforms. Adopter drops the package in, points it at a relay URL (or an OAuth client ID), and adds `GitTicketsCommands()` to their SwiftUI `Commands` builder — or `GitTicketsMenuItemFactory.makeReportIssueItem()` in AppKit. End-users get a native form, screenshots, diagnostics, privacy-banner, and submit. The issue lands directly in the app's GitHub repo.

Phase 2 (also in v1): the user can browse their past submissions inside the app and see developer replies as a thread.

## Quick links

- [Architecture](Architecture) — client SDK + dual auth (relay-default, Device Flow opt-in), data flow.
- [Threat Model](Threat-Model) — what the relay protects against and what it doesn't.
- [Relay Deployment](Relay-Deployment) — how to spin up the Vercel or Cloudflare Worker relay.
- [Device Flow](Device-Flow) — when to use it and how the iOS UX works.
- [Diagnostics & Screenshots](Diagnostics-and-Screenshots) — what we collect, how we redact, capture flow.
- [Getting Started](Getting-Started) — adopter integration walkthrough (stub).
- [Wiki Maintenance](Wiki-Maintenance) — how this wiki is edited and kept safe.

## Roadmap

- **v1.0** — the [20-PR build sequence](Build-Sequence). Closes both phases (submit + my-issues).
- **v1.1** — native rendering of `.github/ISSUE_TEMPLATE/*.yml` Issue Forms.

---
_Last updated: 2026-06-04 — initial wiki seed_
