---
title: PR 2 Complete — Public API Skeleton
type: note
permalink: gittickets/progress/pr-2-complete-public-api-skeleton
tags:
- progress
- pr-2
- public-api
source_sha: 2abeb1abd59498c69229fdb6193ae7b51357f361
reviewed: 2026-06-23
---

PR 2 (Public API skeleton) shipped 2026-06-04. Full public surface exists; auth submitters, UI, and storage are still PR 3+.

## Observations

- [verified] 13/13 tests green on macOS (Swift 6.2.4). #verification
- [verified] iOS Simulator build clean. #verification
- [files-shipped] `Sources/GitTickets/PublicAPI/` — `GitTickets.swift`, `Configuration.swift`, `AuthMode.swift`, `Models.swift`, `GitTicketsError.swift`, `Policies.swift`, `Theme.swift`, `Logger.swift`. #files
- [decision] `SharedSecret` accepts raw `Data`, `base64:`, or `hex:` (with optional `0x` prefix). Hex/base64 inits return `nil` on invalid input — explicit failure, no exceptions. #api
- [decision] `GitTicketsError` includes `CustomStringConvertible` so adopters can surface error messages without writing their own switch. Tested for non-empty descriptions. #api
- [decision] `DiagnosticsRedactor.email/ipv4/ipv6/bearerToken` are static let constants built with `try!` against compile-time-constant regex patterns. A typo would crash on package import — but that's better than silent runtime corruption, and the patterns are covered by PR 5 tests. #api #tradeoff
- [decision] `EnvironmentValues.gitTicketsTheme` declared at `@available(macOS 13.0, iOS 16.0, *)` because the SwiftUI `EnvironmentKey` API is. Type itself is unbounded so non-UI code can reference it. #swiftui #pattern
- [pattern] Multi-file public API split lives entirely under `Sources/GitTickets/PublicAPI/`. Internal modules (Auth/, Networking/, Storage/, Diagnostics/, UI/, Bodybuilder/) come in subsequent PRs and live as siblings. #structure
- [tech-debt] `GitTickets.swift` still uses `nonisolated(unsafe) static var _configuration`. Wrap in an actor once we have async submitters in PR 8. #tech-debt

## Relations

- precedes PR-3-Models-Body-Builder
- realizes [[Architecture — Client SDK + Optional Relay]]
- follows [[PR 1 Complete — Bootstrap Verified]]
