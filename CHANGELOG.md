# Changelog

All notable changes to GitTickets are documented here. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The SDK and the relay templates version independently.

## [2.2.0] — 2026-07-26

### Fixed

- **macOS had no way to refresh an open "My Reports" or Issue Detail window.**
  Both screens used `ScrollView { … }.refreshable { … }`, and on macOS that
  combination installs **nothing** — the AppKit hierarchy is byte-identical to
  applying no modifier, and the `refresh` environment action is not even
  propagated. Only `List` gets an affordance there. So a report filed elsewhere
  could not appear in an open list, and a new reply could not appear in an open
  thread; closing and reopening the window (which re-runs `.task`) was the only
  mechanism.

  This was measured against the shipped views, not inferred — see
  `Harnesses/RefreshAffordance`. On **iOS** the same construction works
  correctly and always did: `.refreshable` installs a `UIRefreshControl` on a
  plain `ScrollView`, so pull-to-refresh was never broken there and is unchanged.

### Added

- **A toolbar Refresh control on both screens**, with a ⌘R keyboard shortcut and
  an accessibility label. This is the only refresh affordance a macOS user can
  reach directly, and it works on both platforms.
- **Automatic re-fetch when the scene becomes active again.** Returning to the
  window picks up new issues and replies without any user action. The first
  activation is deliberately ignored, since the screen's own `.task` has already
  loaded by then.

### Changed — behavior

- **`MyIssuesPolicy.pollInterval` now does something.** It has been public since
  Phase 2 but nothing read it, so no auto-refresh existed under any
  configuration. It now drives a re-fetch loop on both screens, cancelled when
  the screen goes away.

  **The default is unchanged at `0`, which means off**, so adopters on defaults
  see no new network traffic. A negative value is treated as `0` rather than
  spinning. Polling costs a request per screen per interval against your relay
  and GitHub's rate limits — prefer scene reactivation and leave this at `0`
  unless you specifically need live updates.

### Notes for adopters

- Two doc comments were wrong and are corrected. `GitTicketsMyIssuesView`'s
  header claimed "the iOS `.refreshable` gesture on macOS too" (false), and
  `MyIssuesPolicy.pollInterval` claimed manual refresh via "⌘R on macOS" when no
  such shortcut existed. Both are now true statements rather than intentions.

## [2.1.0] — 2026-07-26

Additive minor, driven by the ShabuBox integration — a privacy-first macOS
document vault whose in-app reports file to a **public** repository. Every
item here exists because a private document vault reporting into a
world-readable issue tracker has a much lower tolerance for incidental
metadata than a typical app.

No public API was removed or changed in signature. The platform floor is
**unchanged** at macOS 14 / iOS 18.

### Security

- **`SharedSecret(hex:)` and `SharedSecret(base64:)` now reject degenerate
  input that previously produced a usable-but-wrong HMAC key.** Present in
  1.x and 2.0.0. Three cases, all confirmed against the shipped 2.0.0 tag:
  - `SharedSecret(hex: "")`, `"   "` and `"0x"` returned a **non-nil,
    zero-byte key** — zero digits satisfied the even-length check.
  - `SharedSecret(hex: "+1+1")` returned the bytes `01 01`, because
    `UInt8(_:radix:)` honours a leading `+` sign.
  - `SharedSecret(base64: "====")` returned a **one-byte `0x00` key**,
    because `Data(base64Encoded:)` decodes padding-only input to a single
    zero byte, which is non-empty and passed the existing guard.

  These do not leak a secret. They let a misconfiguration produce a
  degenerate, publicly-guessable signing key that **fails silently rather
  than loudly**. If only the app side is degenerate, submissions simply
  break. The dangerous case is both sides degenerate: the relay appears to
  work while providing no authentication at all, so the shared secret stops
  gating relay abuse. All such inputs now return `nil`. No legitimate secret
  is newly rejected — verified that `0b11`, `0xdeadbeef` and `3q2+7w==` still
  decode unchanged.

- **Attachment link text can no longer break out of its markdown link via
  newlines.** `escapeMarkdownLinkText` escaped `\`, `[` and `]` but nothing
  for CR/LF, and APFS permits newlines in filenames — so a crafted filename
  containing a blank line ended the link early and let injected markdown
  render as real formatting. CR/LF now fold to spaces.

### Changed — behavior

- **Absolute paths are now redacted from diagnostics by default.** The new
  `DiagnosticsRedactor.absolutePath` is included in the default redactor
  array, so adopters relying on defaults will see `/Users/...`, `~/...`,
  `/Volumes`, `/private`, `/var`, `/tmp`, `/Applications` and `/Library`
  paths — **including the trailing filename** — replaced with
  `[path redacted]`. This removes the account name and the document name
  from diagnostics, which on a public tracker is the whole point.

  Source-compatible, and nothing was removed. To opt out, pass an explicit
  array: `DiagnosticsPolicy(redactors: [.bearerToken, .email, .ipv4, .ipv6])`.

### Added

- **`PrivacyPolicy.attachmentNames`** (`AttachmentNameDisplay`). Set it to
  `.generic` and attachment links render as "image 1" / "attachment 2"
  instead of the user's filename, so "Tax Return 2024.png" stops becoming
  public link text. Numbering is a single 1-based index across the whole
  list, so the Nth link matches the Nth attachment. Defaults to `.filename`
  (existing behavior). The uploaded object keeps its real name; only the
  markdown link text changes. The dedicated screenshot line was already
  filename-free and is unchanged.
- **`SharedSecret(infoPlistKey:encoding:bundle:)`** — read the relay shared
  secret from the app bundle's `Info.plist`, so it can be fed from a
  gitignored `xcconfig` instead of a literal committed to source. `encoding`
  is deliberately required rather than sniffed: a string like `abcdef` is
  valid as *both* hex and base64, and guessing would silently derive the
  wrong key. **This keeps the secret out of git, not out of an attacker's
  hands** — `Info.plist` ships as plaintext and `plutil -p` reads it. It
  gates casual relay abuse; it does not guard anything.
- **`DiagnosticsRedactor.recommended`** — the ordered built-in set, so custom
  redactor lists can start from a correct base.
- **Full-size preview of a pending attachment** in the compose form. When
  submission is irreversible and public, the user should be able to confirm
  at full size what they are about to publish rather than judging it from a
  48pt tile.

### Notes for adopters

- **Redactor order is load-bearing, and the array you pass is used verbatim.**
  Redactors apply in sequence over already-redacted text, so a replacement
  that inserts spaces (`[ip redacted]`, `[email redacted]`) can truncate a
  later pattern mid-match. `.absolutePath` is therefore placed *before*
  `.email`, `.ipv4` and `.ipv6` in the defaults. If your own redactor must
  win against a built-in, place it before that built-in explicitly — do not
  write `DiagnosticsRedactor.recommended + [mine]`, since appending puts
  yours last, after the built-in has already matched.
- **`.absolutePath` is a floor, not a guarantee.** A space terminates the
  match, so `/Users/ana/Documents/Tax Return.pdf` redacts to
  `[path redacted] Return.pdf` — the account name always goes, but a
  filename containing spaces partially survives. Allowing spaces would let
  the match run off into surrounding log text and eat the triage
  information, which is worse. Backslash-escaped separators
  (`\/Users\/...`) are not matched either. Both limitations are pinned by
  tests so they stay visible.
- **Labels silently dropped by GitHub are already detectable and always
  were** — see `SubmittedIssue.missingLabels` and the `.warning` the SDK
  logs when a requested label doesn't come back. No release was needed for
  this; it is now cross-referenced from the relay docs, where it was missing.

## [2.0.0] — 2026-07-26

**Breaking release.** The supported-platform floor moves up: **macOS 13 → 14
(Sonoma)** and **iOS 16 → 18**. Dropping OS versions that previously worked is
why this is a major version — no public API was removed, renamed, or changed
in signature. Everything else here is subtraction: dead code, no-op
annotations, and a CI configuration that was testing the wrong thing.

### Removed — platform support (BREAKING)

- **`Package.swift` platforms: `.macOS(.v14)` and `.iOS(.v18)`** (were `.v13`
  and `.v16`). Any app whose deployment target is **below macOS 14 or below
  iOS 18 cannot use 2.0.0** — SwiftPM rejects a package whose minimum platform
  version exceeds the consuming target's. Note that on iOS this drops **two**
  releases: **iOS 17 is excluded as well as iOS 16.**
- **If you must stay below macOS 14 / iOS 18, pin `1.0.0`.** Its manifest
  declares `.macOS(.v13)` / `.iOS(.v16)` under `swift-tools-version:5.9`, so it
  is the last release that targets those OSes without being written in the
  Swift 6 language mode. 1.1.0 declares the same runtime floor, but does not
  build on the toolchain its own documentation claims — see the correction on
  the [1.1.0] entry below.
- **A `upToNextMajorVersion` requirement from 1.x will NOT pick this up.**
  `from: "1.0.0"` / `from: "1.1.0"` resolves the range `[1.0.0, 2.0.0)`, which
  excludes 2.0.0 by design. Upgrading is a deliberate act: change the
  requirement to `from: "2.0.0"` (or
  `.upToNextMajor(from: "2.0.0")`) in `Package.swift`, or edit the version rule
  on the package reference in Xcode. Nothing auto-resolves you into the new
  platform floor.

### Two floors, stated separately

These are different things and this release keeps them apart on purpose,
because collapsing them into one sentence is exactly how 1.1.0 shipped a false
compatibility claim.

**Runtime floor — what can run the package:** macOS 14 (Sonoma) and iOS 18.
Declared in `Package.swift` and enforced by SwiftPM.

**Toolchain — what builds the package:** this release deliberately does **not**
assert a minimum Swift or Xcode version. Here is what was actually built and
run:

- **Verified locally on Xcode 26.6 / Swift 6.3.3:** `swift build` with 0
  warnings, `swift test` 210/210 passing, and `xcodebuild` BUILD SUCCEEDED for
  a generic iOS Simulator destination. On a pristine clone,
  `TEST_RUNNER_CI=true xcodebuild test` reports TEST SUCCEEDED with 204 passed
  and 6 skipped (the 6 are the snapshot tests, which skip under CI).
- **Verified on CI with Xcode 26.3 on `macos-15`.** The retargeted workflow
  ran green on the 2.0.0 merge commit — its first green run, and the first in
  this repository's history. The macOS job executed 210 tests (6 snapshot
  tests skipped) and the iOS job executed 198 (30 skipped: keychain-entitlement
  and compile-time platform exclusions). The iOS job resolved its destination
  to a real **iOS 18.6** simulator, so the iOS 18 floor is tested *at* the
  floor rather than only above it.
- **Xcode 16.x is untested, in both directions.** The Swift 6.0 concurrency
  error that broke 1.1.0 lived in code this release deletes, so 2.0.0 may well
  compile on Xcode 16.x — but nobody has tried it, so nothing here claims it
  does or doesn't.
- Two constraints are structural rather than measured: the manifest is
  `swift-tools-version:6.0`, and `.iOS(.v18)` is
  `@available(_PackageDescription 6.0)` — so a toolchain whose manifest API
  predates 6.0 cannot resolve the package at all. That is a manifest-level
  fact, not a statement that we built the package on the oldest toolchain
  satisfying it.

### Removed — code

- **The `OneShotStream` macOS 13 screenshot fallback is gone**
  (net −90 lines). This was **dead-code deletion, not a rewrite.** The
  capture path already had `if #available(macOS 14.0, *)` calling
  `SCScreenshotManager.captureImage` with the identical content filter and
  configuration; the hand-rolled `SCStream` adapter was only the macOS 13
  `else` branch. **Every macOS 14+ user was already on the
  `SCScreenshotManager` path in production**, so behavior on every supported
  OS is unchanged and the error surface is byte-identical. Deleting it also
  removed the Swift 6.0 concurrency compile error that had been keeping CI
  red.
- **62 `@available` annotations** that became no-ops at the new platform floor
  (`macOS 13.0` / `iOS 16.0` bounds at or below `.v14` / `.v18`), plus 4
  refreshed header comments. **Zero executable lines changed**, and the public
  API surface was proven unchanged with `swift-api-digester`.

### Changed

- **CI now tests the platforms the package actually supports.**
  `runs-on: macos-15`; Xcode pinned to `26.3` instead of `latest-stable` so a
  toolchain bump cannot silently change what "green" means; the job matrix is
  split into generic build destinations and concrete test destinations
  (`iPhone 16, OS=18.6` for iOS). Snapshot tests skip on CI via the
  `TEST_RUNNER_CI` environment variable. A `.gitkeep` removes a spurious
  `Invalid Exclude` warning, and a stale `Package.swift` comment was
  corrected.

### Not in this release

- **No SwiftUI modernization.** This was investigated and deliberately
  declined. `ContentUnavailableView` would have replaced empty-state cards
  that are deliberately designed (tinted icon tile, card surface, hairline
  border, 420pt max width) — that is a visual redesign, not a code reduction.
  `onChange` has zero call sites in the repo. Nothing was changed, so nothing
  is claimed.
- **No public API changes.** No additions, no removals, no signature changes.
  Source compatibility is intact for any adopter already on macOS 14 / iOS 18;
  the breaking part of this release is exclusively the platform floor.

## [1.1.0] — 2026-06-23

> **⚠️ Correction — added 2026-07-26 as part of 2.0.0.**
> The claim below that "**Minimum toolchain is now Swift 6.0 (Xcode 16+)**" is
> **false**, and was never verified against a Swift 6.0 toolchain before being
> published. **v1.1.0 does not build on Xcode 16.2 / Swift 6.0**: the macOS 13
> `SCStream` screenshot fallback in `ScreenshotCapture+macOS.swift` trips an
> actor-isolation error on a `Task { }` capture that Swift 6.0's
> region-based isolation rejects. Later Swift versions accept the same code, so
> in practice v1.1.0 was only ever built on Xcode 26.x. The exact working
> boundary between Swift 6.0 and 6.3.3 was never bisected. The same unverified
> claim also appeared in the v1.1.0 README, `docs/getting-started.md`, and the
> v1.1.0 annotated git tag. The offending code is deleted in 2.0.0, and 2.0.0
> states what was tested instead of asserting a minimum — see [2.0.0] above.
> The original entry is left unedited below, for the record.

Swift 6 language-mode migration. **No runtime-behavior change** — only
concurrency annotations, one deprecated-API rename, and build config.

### Changed

- **Swift 6 language mode.** `swift-tools-version` 5.9 → 6.0 and
  package-level `swiftLanguageModes: [.v6]`; the library and tests now
  compile under the Swift 6 language mode. **Minimum toolchain is now
  Swift 6.0 (Xcode 16+).** Runtime deployment floor is unchanged
  (macOS 13 / iOS 16).
- **`GitTicketsMenuItemFactory` is now `@MainActor`** (along with its
  internal `MenuActionTarget` trampoline) — correct for AppKit menu-item
  construction, which already had to run on the main thread. Source-
  compatible for the documented usage.

### Internal (no API or behavior change)

- `RelaySubmitter`'s two `ISO8601DateFormatter` statics are marked
  `nonisolated(unsafe)` (immutable-after-init; parse-only — the outbound
  wire serialization path is untouched).
- `DeviceInfo` uses `String(validatingCString:)` in place of the
  deprecated `String(validatingUTF8:)` (pure rename, identical semantics).

## [1.0.0] — 2026-06-06

### Added — SDK

- **Public API surface**: `GitTickets.configure(_:) / .submit(_:)`, the
  `Configuration` / `AuthMode` / `Report` / `SubmittedIssue` value types,
  `GitTicketsError` (13 cases incl. distinct device-flow states),
  `GitTicketsTheme` (accent / fonts / corner radius / header image /
  submit button style), and `DiagnosticsPolicy` / `PrivacyPolicy` /
  `MyIssuesPolicy`.
- **Two auth modes** dispatching against a single `IssueSubmitter`
  protocol: `RelaySubmitter` (HMAC-signed POSTs to a developer-hosted
  relay) and `DeviceFlowSubmitter` (hand-rolled OAuth Device Flow + token
  store, posts directly to `api.github.com`).
- **UI layer** — `GitTicketsView` (cross-platform SwiftUI form),
  `DeviceFlowSheet` (ASWebAuthenticationSession with ephemeral browser
  session), `GitTicketsCommands` (SwiftUI commands group with
  configurable placement + disabled state),
  `GitTicketsMenuItemFactory.makeReportIssueItem(...)` + `ReportWindowController`
  (macOS AppKit), `GitTicketsViewController` (iOS UIKit container).
- **Diagnostics pipeline** — `DiagnosticsCollector` + default redactor
  chain (bearer-token, email, IPv4, IPv6) + custom redactor support; the
  user-reviewed blob is byte-identical to what's posted.
- **Screenshot capture** — ScreenCaptureKit on macOS 14+ with a 13
  fallback; `UIWindow.drawHierarchy` on iOS; user-initiated only.
- **Storage** — `SubmissionCache` (SQLite) for "My Issues" correlation +
  reply state, `DeviceIdentity` (Keychain) for the per-install UUID,
  `TokenStore` (Keychain) for OAuth tokens. Bundle-id-namespaced services
  so two same-team apps don't share identity or tokens.
- **Privacy manifest** — `PrivacyInfo.xcprivacy` declaring no tracking,
  three collected data types (`OtherDiagnosticData`, `DeviceID`,
  `PhotosorVideos`) all linked-no / tracking-no with `AppFunctionality`
  purpose, plus `DiskSpace` reason `85F4.1` for the diagnostics blob's
  free-disk readout.
- **Theme wiring** — every public `GitTicketsTheme` field consumed by
  the form: accentColor, titleFont, bodyFont, monospacedFont, cornerRadius,
  headerImage (system symbol / named asset / raw bytes), submitButtonStyle.
- **Documentation** under `docs/` — getting-started, relay-deployment,
  device-flow, theming, diagnostics, privacy, threat-model, architecture.
- **Examples** under `Examples/` — `MacSampleApp`, `iOSSampleApp`,
  `AppKitSampleApp` reference integrations.
- **Test coverage** — 203 unit tests on macOS (+6 snapshot baselines),
  plus the iOS Simulator build path validates UIKit + cross-platform code.

### Added — Relay templates (also v1.0.0, versioned independently)

- `relay/vercel/` — Node 20 / TypeScript Vercel Function deployment with
  GitHub App auth, HMAC signature verification, idempotency, rate
  limiting, multipart attachment uploads to Vercel Blob, full
  `/report` + `/attachment` + `/my-issues` endpoints. 37 vitest tests +
  `tsc --noEmit` clean. CI workflow `.github/workflows/relay-vercel.yml`.
- `relay/cloudflare/` — parity Cloudflare Workers port. R2 for
  attachments, KV for rate limit + idempotency (in-memory fallback for
  low-volume). 32 vitest tests. CI workflow
  `.github/workflows/relay-cloudflare.yml`.
- `relay/shared/payload-schema.md` — language-agnostic spec both
  templates implement. HMAC test vector locked across Swift + Node +
  Workers implementations.

### Status

This is the first tagged release. The SDK is feature-complete for
Phase 1; Phase 2 (the "My Issues" in-app reply thread view) is on the
roadmap as a v1.x point release.

## [Unreleased]

_Nothing yet._

---

[2.2.0]: https://github.com/awizemann/GitTickets/releases/tag/v2.2.0
[2.1.0]: https://github.com/awizemann/GitTickets/releases/tag/v2.1.0
[2.0.0]: https://github.com/awizemann/GitTickets/releases/tag/v2.0.0
[1.1.0]: https://github.com/awizemann/GitTickets/releases/tag/v1.1.0
[1.0.0]: https://github.com/awizemann/GitTickets/releases/tag/v1.0.0
[Unreleased]: https://github.com/awizemann/GitTickets/compare/v2.2.0...HEAD
