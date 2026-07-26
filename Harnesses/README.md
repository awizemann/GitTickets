# Harnesses

Throwaway-style apps kept on purpose. They answer questions about **platform
behavior** that unit tests cannot: whether AppKit or UIKit actually installs an
affordance, what SwiftUI puts in the view hierarchy, what a user can really
reach.

These are developer tools. They live outside `Sources/` and outside any target
the root package declares, so nothing here ships to an adopter. `Harnesses/` is
a separate SwiftPM package that depends on the root package by path — building
or testing GitTickets never builds these.

Run them when you are about to make or repeat a claim about platform behavior.
The alternative is asserting from memory, which is how the finding below got
stated backwards the first time.

---

## RefreshAffordance

Answers: **can a user refresh an open GitTickets window, and how?**

```bash
cd Harnesses/RefreshAffordance
swift run ReproHarness     # macOS: three-way container control
swift run SDKHarness       # macOS: the real shipped GitTicketsMyIssuesView
./ios/run-ios-harness.sh   # iOS: needs a booted simulator
```

### What each one is for

| Harness | Question | Method |
|---|---|---|
| `ReproHarness` | Does `.refreshable` do anything on macOS? | Renders ScrollView-plain, ScrollView-refreshable, and List-refreshable side by side and diffs the AppKit hierarchies |
| `SDKHarness` | Does the **shipped** view have a reachable refresh control? | Hosts the real `GitTicketsMyIssuesView`, then scans for both a scroll-view refresh proxy and a Refresh control in the window |
| `ios/` | Does `.refreshable` work on an iOS `ScrollView`? | Scans the UIKit layer for a `UIRefreshControl` on the backing scroll view |

`ReproHarness` deliberately imports **no** SDK code, so it isolates SwiftUI's
behavior from anything GitTickets does. `SDKHarness` imports the real thing, so
findings rest on shipped code rather than on a reconstruction of it.

Each prints its result and exits — no screenshots, no gesture injection, no
accessibility permissions required. That is what makes them re-runnable in CI or
by an agent.

### Measured results (2026-07-26, macOS 26 host, iOS 26.2 simulator)

**iOS — `.refreshable` on a bare `ScrollView` works.**

```
SCAN YES HostingScrollView              ← ScrollView + .refreshable
SCAN YES UpdateCoalescingCollectionView ← List + .refreshable (control)
```

A `UIRefreshControl` is installed on both. The widely-repeated claim that
`.refreshable` only functions on a `List` is **wrong for current iOS**.

**macOS — `.refreshable` on a `ScrollView` does nothing at all.**

```
ScrollView, no .refreshable   → [HostingClipView, NSScroller]   env.refresh: nil
ScrollView + .refreshable     → [HostingClipView, NSScroller]   env.refresh: nil   ← identical
List       + .refreshable     → [..., PlatformRefreshControlProxy]  env.refresh: PRESENT
```

The hierarchy is byte-identical to applying no modifier, and the `refresh`
environment action is not even propagated. Only `List` gets an affordance.

**Consequence, and why `RefreshTriggers.swift` exists:** both
`GitTicketsMyIssuesView` and `IssueDetailView` use `ScrollView + .refreshable`,
so before that change a macOS user had **no way to refresh an open window** —
closing and reopening it, which re-runs `.task`, was the only mechanism. A
newly filed report could not appear in an open list, and a new reply could not
appear in an open thread.

**After the fix**, `SDKHarness` reports:

```
CHECK1 scrollViewRefreshProxy=false        ← still false; the container did not change
CONTROL view(class=NSToolbarItemViewer, help="Refresh reports")
CHECK2 refreshControlFound=true matches=1
VERDICT userReachableRefreshOnMacOS=true
```

**Toolbar placement matters, and it is measured too.** A `.toolbar` applied to a
`NavigationStack` from the OUTSIDE reaches the macOS window toolbar but does NOT
reach the iOS navigation bar. `RefreshTriggers` is therefore applied *inside* the
stack in `GitTicketsMyIssuesView`. The iOS harness renders that exact
arrangement; its screenshot shows the ⟳ button at the trailing edge of the
navigation bar.

### Limits

These check whether the affordance **mechanism** is installed. They do not
synthesize a swipe, so they do not prove a human gesture invokes the closure.
Gesture-level testing needs input injection.

**A SwiftUI toolbar button cannot be detected reliably from inside the process**,
so the iOS harness reports CHECK2 as `LOOK` and the screenshot is the evidence.
Three detection methods were tried and all three are wrong — the details are in
`ios/main.swift` so nobody repeats them:

| Method | Failure |
|---|---|
| `UIView.accessibilityLabel` over the view tree | false negative — SwiftUI never stamps the label on the backing view |
| Any `UIControl` inside `UINavigationBar` | false positive — matches `_UINavigationBarTitleControl`, the title |
| Walking `accessibilityElements` | false negative — SwiftUI builds them lazily for assistive clients |

macOS is different and *is* auto-detectable: the button surfaces as an
`NSToolbarItemViewer` carrying the `help` string, which is what `SDKHarness`
matches on.
