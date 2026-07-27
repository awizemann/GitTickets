---
title: Footgun: .refreshable on ScrollView is a no-op on macOS (works on iOS)
type: note
permalink: gittickets/architecture/footgun-refreshable-on-scrollview-is-a-no-op-on-macos-works
tags: [footgun, swiftui, macos, refresh, my-issues]
source_paths: [Sources/GitTickets/UI/SwiftUI/GitTicketsMyIssuesView.swift, Sources/GitTickets/UI/SwiftUI/IssueDetailView.swift, Sources/GitTickets/PublicAPI/Policies.swift]
source_paths_inferred: false
source_sha: 004173971607eae22ea35087411d8d7a8c8b70b7
created: 2026-07-26
updated: 2026-07-26
---

Measured 2026-07-26 with two throwaway harnesses, not inferred from documentation.

iOS (simulator, iPhone 17 Pro / iOS 26.2): a UIRefreshControl IS attached to the
HostingScrollView backing `ScrollView { ... }.refreshable { }`. Pull-to-refresh
works on iOS. The common belief that `.refreshable` only functions on List is
wrong for current iOS.

macOS: the real shipped GitTicketsMyIssuesView renders one HostingScrollView with
subviews [BackdropView, HostingClipView, NSScrollPocket, NSScroller] — no refresh
proxy. A three-way control (ScrollView plain / ScrollView refreshable / List
refreshable) showed the first two hierarchies identical, with only the List
getting PlatformRefreshControlProxy.

Caveat: this measures presence or absence of the affordance mechanism, not that a
human swipe fires the closure.

The platform asymmetry above is the durable part and is why RefreshTriggers.swift
exists. The SDK-side gap it caused was fixed in v2.2.0: a toolbar Refresh control
(the only affordance a macOS user can reach), a re-fetch when the scene becomes
active, and optional polling. The `.refreshable` calls stay, because they
genuinely work on iOS.

The harnesses that measured all this are checked in at Harnesses/RefreshAffordance
and are re-runnable — prefer re-running them over re-arguing the behavior.

## Observations
- [gotcha] SwiftUI .refreshable on a bare ScrollView installs a UIRefreshControl on iOS (verified iOS 26.2) but installs nothing at all on macOS #swiftui
- [fact] On macOS the refresh environment action is not even propagated into a refreshable ScrollView (reads nil); inside a refreshable List it reads PRESENT #swiftui
- [fact] macOS List + .refreshable attaches a PlatformRefreshControlProxy subview; ScrollView + .refreshable yields a hierarchy identical to applying no modifier at all #swiftui
- [gotcha] FIXED in v2.2.0 — GitTicketsMyIssuesView and IssueDetailView both use ScrollView + .refreshable, which gave macOS no refresh path at all until RefreshTriggers.swift added a toolbar control, scene reactivation, and polling #gittickets
- [constraint] MyIssuesPolicy.pollInterval was public but read nowhere until v2.2.0 wired it to a re-fetch loop; it still defaults to 0 (off), so scene reactivation is the normal refresh path #gittickets
