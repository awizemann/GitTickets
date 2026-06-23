---
title: Footgun — NSMenuItem Target Is Weak
type: note
permalink: gittickets/footguns/footgun-nsmenuitem-target-is-weak
tags:
- footgun
- appkit
- menu
- memory-management
source_sha: 2abeb1abd59498c69229fdb6193ae7b51357f361
reviewed: 2026-06-23
---

`NSMenuItem.target` is a weak reference. If the action target is only retained by the local scope that created the menu item, it deallocates as soon as that scope returns and the menu click silently does nothing.

The fix is to stash the target somewhere the menu item retains strongly — `representedObject` is the conventional spot. Anyone "cleaning up" the representedObject assignment because "it's unused" silently re-breaks the menu.

Discovered while implementing `GitTicketsMenuItemFactory` (PR 13).

## Observations

- [rule] Any `NSMenuItem` whose target is an instance of a custom class created inside a factory function must stash that target in `representedObject` (or another strong reference on the menu item). The factory's local `let target = ...` is not enough — it falls out of scope on return. #appkit #memory-management
- [rule] Lifetime-retention tests for this pattern need to construct the menu item inside an inner scope that returns and check `item.target` is still non-nil afterward. Without the inner scope, ARC keeps the trampoline alive via the enclosing test function's stack frame — false positive. See `test_targetIsRetainedAcrossScope` in `GitTicketsMenuItemFactoryTests`. #testing
- [pattern] The bug is invisible in code review: the factory returns a "fully configured" menu item with `target` and `action` both set. Only runtime testing catches it — and not always, because UI tests that simulate menu clicks immediately after construction don't give ARC time to release. The lifetime test is the right shape: build inside a closure, then read after. #review-pattern
- [related] Same lesson as [[Footgun — Keychain Synchronizable Default Leaks Across iCloud]]: never trust a platform default to be what you assume. Cocoa is full of weak references chosen to break retain cycles in IB-archived nibs — but factory-construction code has the opposite problem. #cocoa

## Relations

- documented_in [[PR 13 Complete — SwiftUI Commands + AppKit Factory]]
- prevents_recurrence_of "menu item silently no-ops after factory function returns"
