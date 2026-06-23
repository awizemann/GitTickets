---
title: Architecture — Client SDK + Optional Relay
type: note
permalink: gittickets/architecture/architecture-client-sdk-optional-relay
tags:
- architecture
- decision
- auth
source_sha: 2abeb1abd59498c69229fdb6193ae7b51357f361
reviewed: 2026-06-23
---

The v1 architecture for GitTickets, decided 2026-06-04.

## Observations

- [decision] Ship TWO auth modes in v1: `.relay(url:sharedSecret:)` (default, no GitHub account for end-users) and `.deviceFlow(clientID:)` (opt-in, user authenticates with their GitHub account). Both production-quality. #auth #decision
- [decision] Relay lives in the same repo under `/relay/` with Vercel + Cloudflare Worker variants. Templates versioned alongside the SDK. #relay #decision
- [decision] Phase 2 ("My Issues" + reply notifications) fully built in v1, NOT deferred. Correlation via opaque UUID embedded as `<!-- gittickets-id: UUID -->` in issue body. #phase2 #decision
- [decision] MIT license. #license #decision
- [decision] Platform floor: macOS 13+ / iOS 16+ (runtime, unchanged). Build toolchain bumped to swift-tools-version 6.0 / Swift 6 language mode at v1.1.0 (was 5.9 through v1.0.0); minimum Xcode 16+. Modern SwiftUI ergonomics worth the floor. See [[Swift 6 Language Mode Migration (v1.1.0)]]. #platforms #decision
- [decision] Zero production Swift dependencies — system frameworks only (CryptoKit, Foundation, Security, SwiftUI, AppKit/UIKit, ScreenCaptureKit, OSLog, SQLite3). Octokit.swift skipped — it doesn't support GitHub App auth and the few endpoints we hit are ~30 LOC of URLSession. Test-only dep: pointfreeco/swift-snapshot-testing. #dependencies #decision
- [fact] GitHub has NO anonymous write surface anywhere — issues, discussions, attachments all require a token. Drives the relay-or-Device-Flow choice. #constraint
- [fact] Sparkle is NOT actually drop-in — devs hand-wire `SPUStandardUpdaterController` to a menu item. We do better by shipping both `GitTicketsCommands()` (SwiftUI) AND `GitTicketsMenuItemFactory.makeReportIssueItem()` (AppKit). #ergonomics #insight
- [pattern] All UI talks to an internal `IssueSubmitter` protocol; `RelaySubmitter` and `DeviceFlowSubmitter` conform. UI never branches on auth mode. #pattern

## Relations

- depends_on [[Footgun — No Anonymous GitHub Write Surface]]
- depends_on [[Footgun — No Public GitHub Attachment API]]
- realized_by [[Build Sequence — 20 PR Plan]]
