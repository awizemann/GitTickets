# Diagnostics

The diagnostics blob is the structured text that lands at the bottom of
every issue body — device model, OS version, app version, free disk
space, optional recent OSLog entries. It's collected once when the form
opens, shown to the user in an expanded `DisclosureGroup` (so they see
exactly what's about to be sent), and inlined into the issue body verbatim
on submit.

**Invariant**: what the user sees in the disclosure is byte-identical to
what gets posted to GitHub. The SDK never re-collects diagnostics at
submit time. The form pre-collects, redacts once, and passes the result
through.

## Default policy

```swift
DiagnosticsPolicy(
    includeOSVersion: true,
    includeAppVersion: true,
    includeDeviceModel: true,
    includeLocale: true,
    includeMemoryPressure: true,
    includeFreeDisk: true,
    osLogSubsystems: [],            // no OSLog by default
    osLogLookback: 300,             // 5 minutes
    redactors: [.bearerToken, .email, .ipv4, .ipv6],
    showByDefault: true             // always true in v1
)
```

Pass an explicit `DiagnosticsPolicy` to `Configuration.diagnostics` to
adjust.

## Opting individual sections out

```swift
let policy = DiagnosticsPolicy(
    includeFreeDisk: false,         // user finds disk space sensitive
    includeMemoryPressure: false
)
```

Sections that are off don't appear in the blob.

## Including OSLog

Pass your bundle identifier (and any sub-system identifiers) into
`osLogSubsystems` to include the last few minutes of OSLog entries from
those subsystems. The lookback defaults to 5 minutes; raise it via
`osLogLookback`.

```swift
DiagnosticsPolicy(
    osLogSubsystems: [Bundle.main.bundleIdentifier ?? "com.myorg.myapp"],
    osLogLookback: 600              // 10 minutes
)
```

The reads use `OSLogStore(scope: .currentProcessIdentifier)` so only the
current process's logs are visible. Lookback failures are silent — the
section is omitted rather than blocking the report.

## Redaction

Redactors run in declaration order. The default pipeline replaces:

- `Bearer <token>` → `Bearer [token redacted]`
- email addresses → `[email redacted]`
- IPv4 addresses → `[ip redacted]`
- IPv6 addresses (including `::` zero-compression) → `[ip redacted]`

Bearer-token redaction runs first so the IP redactors can't accidentally
break a token's surrounding character set.

## Custom redactors

```swift
let licenseKey = DiagnosticsRedactor(
    name: "licenseKey",
    regex: try NSRegularExpression(pattern: #"LIC-[A-Z0-9]{12}"#),
    replacement: "[license redacted]"
)

let policy = DiagnosticsPolicy(
    redactors: [.bearerToken, .email, .ipv4, .ipv6, licenseKey]
)
```

Test custom redactors aggressively. Regex redactors over-match more often
than they under-match — a pattern that looks tight in isolation will
silently swallow real text that incidentally matches its shape. Build a
unit test that runs the redactor over a realistic blob and asserts each
non-matching span survives unchanged.

## Disabling diagnostics entirely

```swift
GitTicketsView()
    .environment(\.gitTicketsTheme, .default)
// The user can untoggle the diagnostics DisclosureGroup; doing so sets
// `report.includeDiagnostics = false` and the blob is omitted from the
// posted body.
```

For programmatic callers using `GitTickets.submit(_:)` directly, pass
`includeDiagnostics: false` to the `Report` initializer.
