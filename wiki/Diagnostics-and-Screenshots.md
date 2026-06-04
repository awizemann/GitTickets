---
title: Diagnostics-and-Screenshots
type: note
permalink: gittickets-wiki/diagnostics-and-screenshots
---

# Diagnostics & Screenshots

What we collect, how the user sees it before submission, and how we redact.

## Collected fields

Auto-collected (always on unless the host opts out via `DiagnosticsPolicy`):

| Field | Source | Why |
| --- | --- | --- |
| OS version | `ProcessInfo.processInfo.operatingSystemVersionString` | Reproducibility |
| App version + build | `Bundle.main.infoDictionary` `CFBundleShortVersionString` / `CFBundleVersion` | Reproducibility |
| Device model | `utsname` → human-readable mapping | "iPhone 15" beats "iPhone15,3" |
| Locale | `Locale.current.identifier` | Localization bugs |
| Free disk | `URLResourceKey.volumeAvailableCapacityKey` | Disk-pressure bugs |
| Memory pressure | `task_info` mach call | OOM bugs |

Opt-in (host specifies subsystems via `DiagnosticsPolicy.osLogSubsystems`):

- Recent OSLog entries via `OSLogStore`, filtered by subsystem + level, within `osLogLookback` (default 5 minutes).

NOT collected without explicit host opt-in:

- IDFA (we don't even import AdSupport).
- Location.
- Contacts, photos, microphone, camera.
- Network state beyond reachability bool.
- Any third-party SDK identifiers.

## Disclosure UX

The diagnostics block is **expanded by default** in the form. The user sees exactly what they're sending before they tap Submit. This is non-negotiable. Trust comes from transparency.

```
┌───────────────────────────────────────┐
│  Report an Issue                      │
│                                       │
│  Title  [........................]    │
│  Body   [........................]    │
│                                       │
│  [📷 Add Screenshot]   [📎 Attach]    │
│                                       │
│  ⓘ This will be posted publicly to    │
│    github.com/owner/repo              │
│                                       │
│  ▼ Diagnostics                        │
│  ┌─────────────────────────────────┐  │
│  │ OS: iOS 17.5 (iPhone 15)        │  │
│  │ App: 1.2.3 (456)                │  │
│  │ Locale: en_US                   │  │
│  │ Free disk: 24.1 GB              │  │
│  │ Memory: nominal                 │  │
│  │ Logs (5 min):                   │  │
│  │   18:42:01 com.app.net warning  │  │
│  │     Request failed: [redacted]  │  │
│  └─────────────────────────────────┘  │
│                                       │
│  [Cancel]              [Submit]       │
└───────────────────────────────────────┘
```

## Redaction pipeline

The diagnostics blob runs through `RedactionPipeline` before display. Default redactors:

- **Email**: `[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}` → `[email redacted]`.
- **IPv4**: `\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b` → `[ip redacted]`.
- **IPv6**: standard regex → `[ip redacted]`.
- **Bearer token**: `Bearer\s+[A-Za-z0-9._\-/+]{16,}` → `Bearer [token redacted]`.

Hosts add custom redactors via `DiagnosticsPolicy.redactors`. The pipeline applies them in order; non-overlapping matches.

**Critical invariant**: the redacted text the user sees in the form is byte-identical to what gets posted. Never apply additional redaction after the user has confirmed. PR 7 (privacy redaction tests, §13.7) verifies this.

## Screenshot capture

### macOS

Primary: ScreenCaptureKit (`SCStream` one-shot frame at `SCContentFilter` of the main display).

Fallback: `CGWindowListCreateImage(.zero, [.optionAll], kCGNullWindowID, [.bestResolution])` for macOS 12 if ever supported.

Permission: Screen Recording, prompted by the first call. If denied, fall back to a "Screen Recording permission required" inline message with a "Open System Settings" button. **Never block submission on missing permission** — let the user submit text-only.

### iOS

`UIGraphicsImageRenderer` rendering the key window (`UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)`). No permission prompt; entire process is in-app.

Status bar capture is intentional — bug reports often involve battery/network state.

### Auto-capture

Never. The Add Screenshot button captures synchronously on tap. Auto-capture in the background is creepy, surprising, and creates a privacy trap. The user is in control.

## Annotation / redaction in v1.0

Simple rectangle mask tool: tap-and-drag to draw an opaque rectangle over a portion of the screenshot. No blur, no arrows, no text labels — those land in v1.1 if there's demand. The 80% case is "hide my email address before submitting."

## Attachment limits

- Single attachment limit: 5 MB.
- Total submission limit: 8 MB (covers attachment + body + diagnostics).
- Image attachments only in v1 (PNG, JPEG, HEIC). Other types in v1.1.

Larger uploads return `413` from the relay → SDK surfaces `.attachmentTooLarge(byteLimit: 5242880)` → UI shows "Image too large (5 MB limit)" inline.

---
_Last updated: 2026-06-04 — initial diagnostics guide_
