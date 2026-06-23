---
title: PR 13 Complete — SwiftUI Commands + AppKit Factory
type: note
permalink: gittickets/progress/pr-13-complete-swiftui-commands-appkit-factory
tags:
- progress
- pr-13
- swiftui
- appkit
- menu
source_sha: 2abeb1abd59498c69229fdb6193ae7b51357f361
reviewed: 2026-06-23
---

PR 13 ships the menu-integration tier. SwiftUI hosts add a single line to `.commands`; AppKit hosts get a fully-wired `NSMenuItem` from a factory call. Both routes converge on `GitTicketsView` — the form from PR 12 is the destination of either trigger.

## Observations

- [verified] 194/194 Swift tests green (was 182 — +12 new). 37/37 Vercel + 32/32 Cloudflare untouched and re-confirmed green. iOS Sim build clean (AppKit files are `#if os(macOS)`-gated). #verification
- [shipped] `Sources/GitTickets/UI/SwiftUI/GitTicketsCommands.swift` — public `Commands` group with an action closure. Placed via `CommandGroup(after: .help)` so it lands at the bottom of the Help menu. Cross-platform (macOS 13 / iOS 16). UI-agnostic on purpose: the host decides whether the action presents a sheet, opens a `Window` scene, or calls into AppKit's `ReportWindowController`. Diverges from Memophant's pattern that hardcodes `openWindow(id:)` — the package can't ship a scene declaration so the closure is the cleanest separation. #pr-13
- [shipped] `Sources/GitTickets/UI/AppKit/GitTicketsMenuItemFactory.swift` (macOS-only). `makeReportIssueItem(title:keyEquivalent:keyEquivalentModifierMask:action:)` returns an `NSMenuItem` whose action selector lives on a tiny `MenuActionTarget` trampoline (`@objc func fire(_:) { action() }`). Default action calls `ReportWindowController.shared.showWindow(nil)` so the menu item works zero-config. #pr-13
- [footgun-locked] `NSMenuItem.target` is a weak reference. If `MenuActionTarget` only lives in the local var that returns the item, it deallocates the moment `makeReportIssueItem` returns and the menu click silently does nothing. The factory stashes the trampoline in `NSMenuItem.representedObject` (which is strong) so its lifetime is tied to the menu item. `test_targetIsRetainedAcrossScope` locks the property — drops the trampoline through a return-from-closure and asserts `item.target` is still non-nil afterward. Worth a footgun memory entry if it's not already documented. #footgun
- [shipped] `Sources/GitTickets/UI/AppKit/ReportWindowController.swift` (macOS-only) — `public final class : NSWindowController` hosting `GitTicketsView` via `NSHostingController`. `shared` process-wide singleton so re-opening from the menu while the window is already visible brings the existing window forward instead of stacking duplicates. `windowFrameAutosaveName = "GitTickets.ReportWindow"` persists window position/size across opens. `showWindow(_:)` replaces `contentViewController` with a fresh `NSHostingController<GitTicketsView>` on each call — discarding the SwiftUI view tree's `@State` so the form starts blank and yesterday's typed-but-abandoned body doesn't leak forward (small privacy win). #pr-13
- [decision] Window recentering on disconnected display — `showWindow` checks `NSScreen.screens` for intersection with the autosaved frame; if the saved position is off-screen (external display unplugged since last session), the window recenters before showing. Otherwise the user opens the menu and the window is "missing" — a real bug pattern users would not understand. #ux
- [scope-alignment] TASKS.md mentioned `MacSampleApp wires both` — the sample app is PR 19's scope (Examples polish). PR 13 delivers the wireable surface; PR 19 will provide the demo. Not a footgun since the public init is documented + tested for use without a sample. #scope
- [shape-match-avoided] Both commands and menu factory route to the same `GitTicketsView` — and both are wired into the package's public namespace. No declared-but-undispatched surface in this PR. `GitTicketsCommands` action default falls back through to `ReportWindowController.shared` on macOS via the factory; SwiftUI hosts on iOS provide the closure explicitly (no AppKit available there anyway). #pattern
- [test-pattern] Lifetime-retention test for `NSMenuItem` target is the kind of regression-lock the audit pattern wants. The bug — drop the trampoline → menu does nothing — would be invisible without the test. A future refactor that "cleans up" the `representedObject` stash would have failed silently in real usage and we'd only catch it via a user report. The test makes the assumption visible. #testing
- [defer] `Examples/MacSampleApp` — PR 19. The wire-up code is essentially three lines for SwiftUI hosts (`.commands { GitTicketsCommands { showingReport = true } }` + a sheet) or three for AppKit hosts (factory call + `helpMenu.addItem(...)`). Documenting this in the package README is PR 17's job. #next
- [defer] Memophant migration: now unblocked. Memophant can drop its inline `GitTicketsReportView.swift` + `GitTicketsCommands.swift` and switch to `GitTickets.GitTicketsView()` + `GitTickets.GitTicketsCommands { ... }` from this package. Five-line diff. Not part of this PR — the user can run that switch when they want to validate the package version end-to-end. #next

## Relations

- follows [[PR 12 Complete — SwiftUI Form]]
- enables Memophant migration off inline GitTicketsReportView (next Memophant session)
- enables PR 19 Examples Polish (MacSampleApp now has wireable surface)
- closes "PR 13 — SwiftUI Commands + AppKit factory" on TASKS.md
