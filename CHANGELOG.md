# Changelog

All notable changes to GitTickets are documented here. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The SDK and the relay templates version independently.

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

[2.0.0]: https://github.com/awizemann/GitTickets/releases/tag/v2.0.0
[1.1.0]: https://github.com/awizemann/GitTickets/releases/tag/v1.1.0
[1.0.0]: https://github.com/awizemann/GitTickets/releases/tag/v1.0.0
[Unreleased]: https://github.com/awizemann/GitTickets/compare/v2.0.0...HEAD
