---
title: Footgun: optional closure before a trailing closure breaks Swift 5 adopters
type: note
permalink: gittickets/conventions/footgun-optional-closure-before-a-trailing-closure-breaks
tags: [footgun, swift, api]
source_paths: [Sources/GitTickets/UI/SwiftUI/GitTicketsMyIssuesView.swift]
source_paths_inferred: false
source_sha: d90706a7d85fb40ac89bbbbf0fa74ed11d284f3a
created: 2026-10-05
updated: 2026-10-05
---

Found 2026-10-05 adding onClose to GitTicketsMyIssuesView. The package compiles in Swift 6 mode, so its own tests never see Swift 5 trailing-closure behaviour — adopters' app targets often do.

## Observations
- [gotcha] Adding a second defaulted closure parameter after an existing one changes what `X { ... }` binds to in Swift 5 language mode (SE-0286 backward scan) — only a deprecation warning, silent behaviour change #swift #api
- [convention] When adding a closure parameter to a public init that callers use with a trailing closure, keep the old init intact and add an overload whose new closure has NO default; verify with a scratch package that has one .v5 and one .v6 target #api
- [fact] GitTicketsMyIssuesView keeps init(onNew:) unchanged and adds init(onNew:onClose:) with non-defaulted onClose for exactly this reason #my-reports
