---
title: PR 14 Complete — UIKit Container
type: note
permalink: gittickets/progress/pr-14-complete-uikit-container
tags:
- progress
- pr-14
- uikit
- ios
source_sha: 7a91c04dc0c63debdc49916f60c1b50cfd90c3f6
reviewed: 2026-06-24
reviewed_by: human
---

PR 14 ships the iOS-side mirror of PR 13's macOS-only AppKit factory: a single thin `UIHostingController<GitTicketsView>` subclass that lets UIKit hosts present the form via the standard `present(_:animated:)` / `pushViewController(_:animated:)` patterns.

## Observations

- [verified] macOS 197/197 swift test green. iOS Sim build clean. iOS Sim XCTest: 191 tests run, 2 new UIKit tests pass, 26 pre-existing Keychain-entitlement failures (NOT caused by PR 14 — captured in [[Footgun — iOS Sim XCTest Has No Keychain Entitlement]] + flagged on TASKS.md). 37/37 Vercel + 32/32 Cloudflare untouched. #verification
- [shipped] `Sources/GitTickets/UI/UIKit/GitTicketsViewController.swift` (`#if os(iOS)`). `public final class : UIHostingController<GitTicketsView>` — subclassing rather than child-VC embed because the hosting controller already handles safe-area / sizeThatFits / layout-pass bridging. Default `title = "Report an Issue"` for navigation-bar presentation. Programmatic-only init: `init(coder:)` is marked `@available(*, unavailable)` because the rootView depends on `GitTickets.configuration` having been set at launch — IB instantiation can't express that dependency. #pr-14
- [decision] Form Cancel button uses `@Environment(\.dismiss)` which UIKit auto-wires to whichever presentation context the controller's in. Present modally → dismiss closes the modal. Push onto nav → dismiss pops the stack. No custom bar buttons needed by default; hosts that want their own can add via `navigationItem.leftBarButtonItem` after init. Matches the macOS form's environment-driven Cancel behavior — adopters don't have to learn two patterns. #decision
- [scope-alignment] TASKS.md mentioned `iOSSampleApp UIKit variant` — sample app is PR 19's scope, same split as PR 13's MacSampleApp. PR 14 delivers the wireable surface; PR 19 provides the demo. #scope
- [shape-match-avoided] The class is a single-method wrapper around the existing `GitTicketsView()` public init. No declared-but-undispatched surface: present the VC → see the SwiftUI form → submit fires through `GitTicketsView` → `GitTickets.submit(_:)` → configured submitter. The iOS Sim XCTest pass-rate for my 2 new tests confirms the dispatch end-to-end. #pattern
- [discovered] **iOS Sim XCTest has no Keychain entitlement.** 26 pre-existing Keychain-using tests fail with `errSecMissingEntitlement (-34018)` on iOS Sim. Prior sessions only built for iOS Sim, never tested. Wrote a footgun memory note + TASKS.md item for the fix (host-app target / `kSecUseDataProtectionKeychain` / Sim-skip with marker). The Keychain code itself works on real iOS devices — this is purely an SPM test-runner limitation. CI implication: do NOT enable `xcodebuild test` for iOS Sim in CI until this is fixed, or the workflow goes permanently red on a non-bug. #discovery
- [test-pattern] iOS-only XCTest cases compile under `#if os(iOS)` in the test target. They contribute nothing to `swift test` (macOS) totals but run under `xcodebuild -destination 'platform=iOS Simulator,name=...' test`. Verifies UIKit code can be exercised, not just compiled — caught for the first time in PR 14 that we'd been over-relying on build-only verification. Should backport the same pattern for any future macOS Catalyst paths. #testing
- [defer] `iOSSampleApp` UIKit variant — PR 19. Three-line wire-up for hosts (instantiate `GitTicketsViewController`, wrap in `UINavigationController`, present). #next

## Relations

- follows [[PR 13 Complete — SwiftUI Commands + AppKit Factory]]
- discovered [[Footgun — iOS Sim XCTest Has No Keychain Entitlement]]
- enables PR 19 iOSSampleApp (UIKit variant now has wireable surface)
- closes "PR 14 — UIKit container" on TASKS.md
