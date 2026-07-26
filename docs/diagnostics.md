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
    redactors: DiagnosticsRedactor.recommended,  // see Redaction below
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

Redactors run in declaration order. The default is
`DiagnosticsRedactor.recommended`, which is
`[.bearerToken, .absolutePath, .email, .ipv4, .ipv6]` and replaces:

- `Bearer <token>` → `Bearer [token redacted]`
- absolute paths, **including the trailing filename** → `[path redacted]`
- email addresses → `[email redacted]`
- IPv4 addresses → `[ip redacted]`
- IPv6 addresses (including `::` zero-compression) → `[ip redacted]`

### Order is load-bearing

Each redactor matches against text the previous ones have already rewritten.
Because replacements like `[ip redacted]` and `[email redacted]` introduce
spaces and brackets, a replacement made *inside* a longer pattern can
truncate that longer pattern's match and leave its tail in the output.

That is why `.bearerToken` runs first — an IP-shaped substring inside a token
would otherwise break the token's character set and leak the remaining
halves — and why `.absolutePath` runs before `.email` and the IP redactors:
an address rewritten inside a path would cut the path match short and strand
the filename, which is exactly the thing you were redacting.

**The array you pass is applied verbatim.** The SDK does not reorder it, so
the ordering is yours to get right.

### What `.absolutePath` covers, and what it doesn't

It matches `/Users`, `~/`, `/Volumes`, `/private`, `/var`, `/tmp`,
`/Applications` and `/Library` prefixes and consumes the trailing filename.
It deliberately leaves `/System`, `/usr`, `/opt`, `/bin` and `/etc` alone —
those carry no user identity and keep stack traces readable.

It is a floor, not a guarantee:

- **A space ends the match.** `/Users/ana/Documents/Tax Return.pdf` becomes
  `[path redacted] Return.pdf`. The account name always goes, but a filename
  containing spaces partially survives. Allowing spaces would let the match
  run off into the surrounding log line and eat the triage text, which is a
  worse trade.
- **Backslash-escaped separators are not matched** — `\/Users\/ana\/x.pdf`
  passes through. Swift's `JSONEncoder` does not escape forward slashes, so
  the common JSON form is covered; some JavaScript and PHP encoders are not.

If you need to beat either limitation for paths you control — say, your own
container directory, whose document names contain spaces — write a redactor
for that specific shape and **place it before `.absolutePath`**:

```swift
let myContainer = DiagnosticsRedactor(
    name: "myContainer",
    regex: try NSRegularExpression(pattern: #"/Users/[^/]+/Library/Containers/com\.example\.app/\S.*"#),
    replacement: "[path redacted]"
)

// Correct — yours matches first, on the untouched text.
DiagnosticsPolicy(redactors: [.bearerToken, myContainer, .absolutePath, .email, .ipv4, .ipv6])

// WRONG — appending puts yours last, after .absolutePath has already
// truncated the very match you were trying to widen.
DiagnosticsPolicy(redactors: DiagnosticsRedactor.recommended + [myContainer])
```

Appending to `.recommended` is fine for patterns that are independent of the
built-ins (a license key, an internal ID). It is the wrong shape whenever
your redactor needs to win against one.

## Custom redactors

```swift
let licenseKey = DiagnosticsRedactor(
    name: "licenseKey",
    regex: try NSRegularExpression(pattern: #"LIC-[A-Z0-9]{12}"#),
    replacement: "[license redacted]"
)

let policy = DiagnosticsPolicy(
    redactors: DiagnosticsRedactor.recommended + [licenseKey]
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
