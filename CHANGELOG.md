# Changelog

All notable changes to GitTickets are documented here. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The SDK and the relay templates version independently.

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

### Added
- Initial repo scaffolding: `Package.swift` (Swift 5.9, macOS 13+, iOS 16+), MIT `LICENSE`, README, contributing/security/changelog files, GitHub Actions CI on macOS + iOS sim, Swift Package Index manifest.
- Stub `GitTickets.configure(_:)` entry point returning `.notConfigured` until implemented.

---

[1.0.0]: https://github.com/alanw/GitTickets/releases/tag/v1.0.0
[Unreleased]: https://github.com/alanw/GitTickets/compare/v1.0.0...HEAD
