---
title: README
type: note
permalink: gittickets-design/design-handoff-gittickets-views-generic/readme
---

# Handoff: GitTickets — `GitTicketsView` & `IssueDetailView` redesign (Generic / brand-neutral)

## Overview

This package redesigns the two main SwiftUI screens of the **GitTickets** Swift
package — a drop-in "Report an Issue / My Reports" surface backed by an app's
own GitHub repo (macOS 13+ / iOS 16+, SwiftUI only, no third-party deps):

1. **`GitTicketsView`** — the report form (kind picker, title, description,
   diagnostics, privacy/consent, submit).
2. **`IssueDetailView`** — the detail screen opened from "My Reports" (original
   report + replies thread, with empty/error states).
3. **`GitTicketsMyIssuesView`** — the "My Reports" list (the entry point that
   pushes the detail; unread-reply badges, empty/error states).

This is the **brand-neutral** edition: no design-system identity. The demo accent
is the **platform-default system blue** — the most universally compatible choice
for a drop-in package that's meant to sit inside *any* host app. In practice the
package inherits each host app's own accent via `GitTicketsTheme.accentColor ??
Color.accentColor`, so the blue is only what the reference render shows when no
host accent is supplied.

The redesign goals: a clear top-to-bottom hierarchy (**privacy/trust → what's
wrong → what we'll send → submit**), a privacy banner and consent toggle that read
as **one trust flow**, a detail view that surfaces the user's **cached original
report** (so it's never a header over a void), and a **focused empty/error card**
instead of a banner floating in space.

## About the design files & what's in this bundle

This bundle contains both the production-intended SwiftUI implementation and an
HTML visual spec.

- **`swiftui/`** — six paste-ready Swift files. These are the actual
  implementation, written against the package's real public APIs (`Report`,
  `DiagnosticsBlob`, `DiagnosticsCollector`, `RepoCoordinate`, `PrivacyPolicy`,
  `GitTicketsTheme`, `GitTickets.submit`). Drop them into
  `Sources/GitTickets/UI/SwiftUI/`. **The Swift is theme-agnostic** — it resolves
  to native system surface colors and the host/theme accent, so it is byte-for-
  byte the same code whether your default accent is blue, green, or anything else.
- **`reference/GitTickets Redesign (Generic).html`** — the **visual spec**: a
  static HTML render of both screens in macOS + iOS frames, light + dark, in the
  neutral palette. It is a *design reference*, **not** code to ship. Open it in a
  browser; toggle Light/Dark top-right. Its neutral token values live in
  `reference/assets/tokens-generic.css`.

The task for a developer/Claude Code is to **integrate the `swiftui/` files into
the GitTickets package**, wire the four `// EXISTING:` seams to the package's real
building blocks, add one small cache lookup, and confirm the result matches the
HTML reference.

## Fidelity

**High-fidelity.** The HTML reference is the exact intended look (final colors,
type, spacing, states), and the SwiftUI reproduces it natively. The SwiftUI uses
system semantic colors (`.windowBackgroundColor`,
`.secondarySystemGroupedBackground`, `Color.primary.opacity(…)` hairlines, etc.)
so the package adapts to light/dark and any host accent automatically — the HTML's
system blue is just the demo accent (`GitTicketsTheme.accentColor`), not a
required palette.

## Locked design decisions

| Decision | Chosen | Where |
|---|---|---|
| Form field style | **Option B — flat bordered fields** with focus rings | `GitTicketsView.fieldStyle = .flat` |
| Detail report placement | **Option 1 — distinct "Your report" card** above the thread | `IssueDetailView.placement = .card` |

The other branches (`.insetGrouped`, `.firstInThread`) remain behind those
constants and can be deleted once you're certain, or kept as options.

---

## Screen 1 — `GitTicketsView` (report form)

**Purpose:** the user files a bug / feature request / question, reviews the
diagnostics that will be attached, consents, and submits. Presented in a sheet
(macOS window or iOS sheet/full-screen).

**Layout:** a `ScrollView` with a single left-aligned column capped at **640pt
wide** (centered on wide macOS windows), `padding(20)`, vertical `spacing: 24`. A
**pinned bottom bar** sits outside the scroll via `.safeAreaInset(edge: .bottom)`
so Cancel + Submit are always reachable. iOS: large navigation title; macOS:
inline window title + an in-content title in the header.

**Top-to-bottom components:**

1. **Header** — accent-tinted rounded tile (cornerRadius + 1) holding the theme's
   header icon (default SF Symbol `exclamationmark.bubble`, 26pt, accent), beside
   a one-line subtitle ("Tell us what happened — it lands as a GitHub issue we can
   reply to.", footnote, secondary). macOS also shows the bold title here.

2. **Privacy section** — eyebrow "PRIVACY" (caption2 semibold, 0.7 tracking,
   secondary) above the **TrustBanner**: an accent-tinted surface
   (`accent.opacity(0.12)` fill, `accent.opacity(0.28)` 1px border) with
   `lock.shield` icon + the resolved privacy copy (footnote) + a "Public
   repository" / "Visible to maintainers" label (caption, `globe`/`person.2`).
   - Copy (public): *"Your report is filed publicly to {owner}/{name} — anyone can
     read it."* Private: *"Your report is visible to the maintainers of
     {owner}/{name}."* Honors `PrivacyPolicy.bannerText` override.

3. **"What's wrong" section** — eyebrow "WHAT'S WRONG", then:
   - **Kind picker** — three selectable cards (`ReportKind.allCases`). Row on
     macOS, stacked on iOS, `spacing: 8`. Icon tile (30×30, radius 7), title
     (subheadline semibold), one-line hint (caption secondary). Selected = accent
     border 1.5px, accent-tint fill, accent icon tile (white glyph), checkmark;
     120ms easeInOut. Bug → `ladybug` "Something's broken"; Feature → `lightbulb`
     "An idea to improve"; Question → `questionmark.circle` "How does this work?".
   - **Details fields (Option B — flat):** vertically stacked, `spacing: 12`. Each
     field has a caption-semibold secondary label over a bordered control
     (`GTSurface.card` fill, `hairlineStrong` 1px border, theme cornerRadius).
     Focused: accent 1.5px border + 3px `accent.opacity(0.28)` ring, 120ms.
     **Title** = single-line `TextField`. **Description** = `TextEditor`,
     `minHeight: 92`, hidden scroll bg, placeholder, monospaced `count / 4000`
     counter (tertiary). **Attachments** = dashed accent "Add image" button
     (`photo`) + `ScreenshotThumbnail`s.

4. **Diagnostics section** — eyebrow "DIAGNOSTICS WE'LL ATTACH", then the
   **DiagnosticsCard**. Header: `checkmark.shield` (accent) + "Diagnostics"
   (footnote semibold) + subtitle (caption secondary) + chevron (0°/−90°).
   **Always expanded by default** (transparency is load-bearing). Body: the
   `DiagnosticsBlob.text` in the theme's monospaced font, scroll capped at 220pt,
   with every `[… redacted]` / `Bearer [token redacted]` token highlighted (amber
   foreground, `0.16` amber background, semibold). Footer: green checkmark +
   "Redacted on-device — what you see is exactly what's sent." + a "▢ redacted"
   legend swatch.

5. **Consent + action bar** (pinned, in `.safeAreaInset`):
   - **ConsentRow** (when `PrivacyPolicy.requireExplicitConsent`) — the SAME
     accent-tinted surface as the TrustBanner (this links them into one trust
     flow). 22×22 accent checkbox (fills accent + white check when checked) +
     consent copy (footnote) + "Same place the banner points to. Required before
     you submit." (caption secondary). Whole row toggles.
   - **ActionBar** — `.regularMaterial` bg, top hairline. "Cancel" (`.bordered`,
     large) left; spacer; **Submit** right — `paperplane.fill` + "Submit issue"
     (or `ProgressView` + "Submitting…"), styled per
     `GitTicketsTheme.submitButtonStyle`, tinted to the accent. Disabled until
     title & description are non-empty and (if required) consent is checked.

**Behavior / state:** `kind`, `title`, `bodyText`, `consented`,
`diagnosticsExpanded` (true), `diagnostics`, `screenshot`, `attachments`,
`isSubmitting`, `submitError`. On `.task`, collect diagnostics **once** via
`DiagnosticsCollector.collect(policy:logger:)` so the displayed blob is byte-
identical to what's submitted. Submit builds a `Report(…)` and calls
`try await GitTickets.submit(report)`; success → `onSubmitted(issue)` + `dismiss()`;
failure → `.alert`.

---

## Screen 2 — `IssueDetailView`

**Purpose:** review a filed report and the maintainer thread. Inside the My-Reports
`NavigationStack` (inline title "Issue #N" on both platforms).

**Layout:** `ScrollView` → left column capped at **680pt**, `padding(20)`,
`spacing: 20`. `.refreshable` + `.task` drive a loading→loaded→failed phase.

**Components:**

1. **IssueHeader** — meta row: `KindBadge` (kind icon + label, capsule tinted to a
   quiet semantic hue — bug=red, feature=amber, question=blue, each `0.14` bg) +
   `StatusBadge` ("Open", green `circle`) + trailing monospaced `#128` (tertiary).
   Then **title** (`.title2.bold`), then caption submeta ("Filed {date} · {n}
   replies · last reply {relative}", 3px dot separators), then **"Open on GitHub"**
   `Link` (`arrow.up.right.square`, `.bordered`, `.primary` tint).

2. **ReportCard ("Your report" — Option 1)** — card surface. Header strip
   (accent-tint bg): "YOU" avatar (accent) + "Your report" (footnote semibold) +
   submitted date (caption secondary). Divider. Body: `MarkdownBody` of the cached
   report + (if diagnostics attached) a divider and a quiet "✓ Diagnostics attached
   · View on GitHub" line.

3. **Thread or state:**
   - **loaded, has replies:** "Replies / {count}" label + trailing hairline, then
     `CommentRow`s — 30pt avatar (initials; maintainer=blue, else secondary) +
     name (footnote semibold) + "MAINTAINER" `RolePill` + relative time, markdown
     body in a card-surfaced bubble.
   - **loaded, empty:** `IssueStateCard(.noReplies)`.
   - **failed:** `IssueStateCard(.error)`.

4. **IssueStateCard (empty/error)** — a centered, card-surfaced focused card
   (cornerRadius + 4) pinned **below** the ReportCard so the screen always has
   substance. 52×52 rounded icon tile (`ellipsis.bubble` secondary for empty /
   `exclamationmark.triangle` red for error, `0.14` tint). Title (`.headline`),
   centered message (footnote secondary, max 300pt). Actions: "Open on GitHub"
   (`.bordered`, `.primary`) always; "Retry" (`.borderedProminent`, accent) only
   on error.
   - Empty: *"Your report is saved above. We'll show replies here as soon as a
     maintainer responds."* Error: *"…Replies live on GitHub — check your
     connection and try again."*

**State:** `phase: .loading | .loaded([IssueComment]) | .failed(String)`; `reload()`
awaits the injected `loadComments` closure.

---

## Screen 3 — `GitTicketsMyIssuesView` (My Reports list)

**Purpose:** the entry point to the detail screen — lists the user's past
submissions so they can track replies. Root of a `NavigationStack`; large title
on iOS, inline on macOS; ⌘R (macOS) / pull-to-refresh (iOS).

**Layout:** a `ScrollView` + `LazyVStack` of tappable card rows (`spacing: 8`),
column capped at 680pt, `padding(20)`. Rows are `NavigationLink(value: issue)`;
`.navigationDestination(for: SubmittedIssue.self)` builds the `IssueDetailView`.
Sorted by latest activity (`latestReplyAt ?? createdAt`, descending).

**Row (`MyReportRow`):** leading 36×36 kind icon tile (tinted to the kind's quiet
hue; neutral dashed circle when kind unknown) · title (callout semibold, 1 line)
with a leading accent **unread dot** when `unreadReplyCount > 0` · submeta
(`#128` monospaced · Open/Closed status dot) · trailing column: an accent
**"N NEW"** capsule (when unread) over the relative activity time · chevron on iOS.
Card surface, hairline border, soft 1px shadow; hover lifts `translateY(-1px)`.

**States:** `.loading` (centered `ProgressView`); `.loaded([])` → focused empty
card (`tray` icon, "No reports yet", optional "Report an issue" button);
`.failed` → focused error card with Retry. Both states are centered cards pinned
in the content, not voids.

**Inputs:** `loadIssues` (typically `GitTickets.cachedSubmissions()`), `kindFor`
(defaults to the proposed `cachedReport(for:)?.kind`), `isClosed` (optional —
`SubmittedIssue` carries no open/closed state today, so rows read "Open" unless
you supply it), `onNew` (optional "Report an issue" action wired to present
`GitTicketsView`), and `detail` (builds the pushed `IssueDetailView`).

---

## Design tokens (neutral)

The SwiftUI resolves to **native system colors** for surfaces; the HTML reference
uses the neutral token layer (`reference/assets/tokens-generic.css`). Equivalences:

| Role | SwiftUI | HTML neutral (light / dark) |
|---|---|---|
| Accent (theme-driven) | `theme.accentColor ?? .accentColor` | `#007AFF` / `#0A84FF` (system blue) |
| Accent tint (trust surfaces) | `accent.opacity(0.12)` | `rgba(0,122,255,.10)` / `.18` |
| Card surface | `.controlBackgroundColor` / `.secondarySystemGroupedBackground` | `#FFFFFF` / `#2C2C2E` |
| Ground | `.windowBackgroundColor` / `.systemGroupedBackground` | `#F4F5F7` / `#1C1C1E` |
| Hairline | `Color.primary.opacity(0.09)` | `rgba(60,60,67,.13)` / `rgba(235,235,245,.12)` |
| Hairline strong | `Color.primary.opacity(0.14)` | `rgba(60,60,67,.22)` / `rgba(235,235,245,.20)` |
| Warning (redaction highlight) | amber `#C77B2E` @ 0.16 bg | `--warning` / `--warning-tint` |
| Success (status) | green `#1C9E5E` | `--success` |
| Danger (bug/error) | red `#E0544E` | `--destructive` |
| Info (question/maintainer) | blue `#2F7BD6`/`#007AFF` | `--info` / `--tier-wiki` |

- **Radii:** all from `GitTicketsTheme.cornerRadius` (default 8); cards
  `cornerRadius + 1`, state card `+ 4`, small tiles `7`, checkbox `6`, pills
  `Capsule`.
- **Spacing:** 4px grid — section gaps 24 (form) / 20 (detail), field stack 12,
  card padding 14, button padding ~9–12.
- **Type:** native text styles (`.title2`, `.headline`, `.footnote`, `.caption`,
  `.caption2`) + the theme's `titleFont` / `bodyFont` / `monospacedFont`. Eyebrows
  caption2 semibold, 0.7 tracking, uppercased.
- **Motion:** 120ms easeInOut for selection/focus; 220ms for diagnostics disclosure.

## `// EXISTING:` integration seams

The package's own UI files weren't present at `main`, so these are stubbed with
clear seams — wire them to your real building blocks:

1. **`MarkdownCommentView`** — `IssueDetailComponents.swift › MarkdownBody` renders
   inline markdown via `Text(.init:)`; swap in `MarkdownCommentView(markdown:)` for
   full markdown.
2. **`ScreenshotThumbnail`** — `GitTicketsView.attachmentThumbnails` uses a
   placeholder tile; replace with `ScreenshotThumbnail(data:)`.
3. **`PrivacyBanner` / `DiagnosticsDisclosure`** — superseded by `TrustBanner` /
   `DiagnosticsCard`; rename/wrap if you need the old public symbol names.
4. **Attachment picker** — `GitTicketsView.addAttachment()` is empty; wire to your
   `PhotosPicker` (iOS) / `NSOpenPanel` (macOS) flow.

## One proposed package addition

`IssueDetailView` needs the cached original body. `GitTickets.cachedSubmissions()`
already returns the list; add a sibling lookup backed by `SubmissionRecord.body`
(+ `kind`):

```swift
extension GitTickets {
    /// The cached, as-submitted report for a past submission, if present.
    public static func cachedReport(for id: UUID) -> CachedReport? { … }
}
```

`CachedReport` (kind, body, submittedAt, includedDiagnostics) is defined in
`IssueDetailView.swift`. `CachedReport.body` should be the user's authored text
(diagnostics section + `<!-- gittickets-id -->` marker stripped — `MarkdownBody`
strips the marker defensively regardless).

## Presenting

```swift
// Form
.sheet(isPresented: $reporting) {
    GitTicketsView { issue in /* e.g. route to detail */ }
        // no .environment(\.gitTicketsTheme, …) → inherits the host's Color.accentColor
}

// Detail (inside the My Reports NavigationStack)
IssueDetailView(
    issue: submittedIssue,
    cachedReport: GitTickets.cachedReport(for: submittedIssue.id),
    loadComments: { try await myCommentsFetch(submittedIssue) }
)
```

## Files in this bundle

```
swiftui/
  GitTicketsTheme+Support.swift     theme resolution, native surfaces, redaction highlighter, semantics
  GitTicketsSupportingViews.swift   kind cards, TrustBanner, ConsentRow, DiagnosticsCard, card surface
  GitTicketsFormFields.swift        flat/inset field styles + pinned ActionBar
  GitTicketsView.swift              the report form (fieldStyle = .flat locked)
  IssueDetailView.swift             detail screen + header/badges; CachedReport + IssueComment (placement = .card locked)
  IssueDetailComponents.swift       ReportCard, ReporterPost, CommentRow, IssueStateCard
  GitTicketsMyIssuesView.swift      My Reports list + MyReportRow + empty/error states
reference/
  GitTickets Redesign (Generic).html   visual spec (macOS + iOS, light + dark, neutral)
  render.css, assets/tokens-generic.css supporting styles + neutral tokens (reference only)
```

**Targets:** macOS 13+ / iOS 16+. **No third-party dependencies.** All public
types referenced are the package's real APIs. The `swiftui/` files are identical
to the branded handoff — only the reference render's demo accent differs.