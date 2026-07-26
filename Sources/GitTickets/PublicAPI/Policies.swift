import Foundation

// MARK: - DiagnosticsPolicy

/// Controls what diagnostic information the SDK collects and how it's redacted
/// before submission.
///
/// The collected blob is always shown to the user (expanded by default) in
/// the report form before submission. Trust comes from transparency.
public struct DiagnosticsPolicy: Sendable {

    /// Include `ProcessInfo.processInfo.operatingSystemVersionString`. Default: `true`.
    public var includeOSVersion: Bool

    /// Include `CFBundleShortVersionString` + `CFBundleVersion`. Default: `true`.
    public var includeAppVersion: Bool

    /// Include the human-readable device model (e.g. "iPhone 15"). Default: `true`.
    public var includeDeviceModel: Bool

    /// Include `Locale.current.identifier`. Default: `true`.
    public var includeLocale: Bool

    /// Include current memory pressure state. Default: `true`.
    public var includeMemoryPressure: Bool

    /// Include free disk space. Default: `true`.
    public var includeFreeDisk: Bool

    /// `OSLog` subsystems to tail. Empty (default) means no logs are collected.
    public var osLogSubsystems: [String]

    /// How far back to read OSLog entries. Default: 5 minutes.
    public var osLogLookback: TimeInterval

    /// Redactor pipeline applied to free-form diagnostics text before display.
    ///
    /// Default: ``DiagnosticsRedactor/recommended``.
    ///
    /// ## Order is part of the contract
    ///
    /// Redactors run in array order and each one sees the output of the
    /// previous one. Every replacement inserts `[`, `]`, and spaces —
    /// characters that appear in no token, address, or filesystem path. So a
    /// redactor that fires *inside* a region a later redactor was supposed to
    /// match will split that region in two and the later redactor matches
    /// only the head, leaving the tail in the clear. Two instances of this:
    ///
    /// - `.bearerToken` must precede `.ipv4`/`.ipv6`, or an IP-shaped
    ///   substring inside a JWT breaks the token charset and the remaining
    ///   halves of the token leak.
    /// - `.absolutePath` must precede `.email` and `.ipv4`/`.ipv6`, or an
    ///   address or address-like segment inside a path truncates the path
    ///   match and **strands the filename** —
    ///   `/Users/ana/Logs/10.0.0.5/Invoice.pdf` becomes
    ///   `[path redacted][ip redacted]/Invoice.pdf`.
    ///
    /// The array you pass is used exactly as given; the SDK never reorders
    /// it. If you are adding your own redactor, start from the vetted order
    /// rather than rebuilding the list by hand:
    ///
    /// ```swift
    /// policy.redactors = DiagnosticsRedactor.recommended + [myRedactor]
    /// ```
    public var redactors: [DiagnosticsRedactor]

    /// Whether the diagnostics block is shown expanded by default in the form.
    /// Always `true` in v1 — transparency is non-negotiable.
    public var showByDefault: Bool

    public init(
        includeOSVersion: Bool = true,
        includeAppVersion: Bool = true,
        includeDeviceModel: Bool = true,
        includeLocale: Bool = true,
        includeMemoryPressure: Bool = true,
        includeFreeDisk: Bool = true,
        osLogSubsystems: [String] = [],
        osLogLookback: TimeInterval = 300,
        redactors: [DiagnosticsRedactor] = DiagnosticsRedactor.recommended,
        showByDefault: Bool = true
    ) {
        self.includeOSVersion = includeOSVersion
        self.includeAppVersion = includeAppVersion
        self.includeDeviceModel = includeDeviceModel
        self.includeLocale = includeLocale
        self.includeMemoryPressure = includeMemoryPressure
        self.includeFreeDisk = includeFreeDisk
        self.osLogSubsystems = osLogSubsystems
        self.osLogLookback = osLogLookback
        self.redactors = redactors
        self.showByDefault = showByDefault
    }

    /// The default policy — collects everything system-level, no OSLog,
    /// standard redactor pipeline.
    public static let `default` = DiagnosticsPolicy()
}

/// A single regex-based substitution applied to the diagnostics blob.
///
/// The pipeline runs redactors in declaration order; the redacted text the
/// user sees in the form is byte-identical to what gets posted to GitHub.
///
/// ## Ordering hazard
///
/// Order is significant and getting it wrong causes **under**-redaction, not
/// over-redaction. Each replacement inserts brackets and spaces, which are
/// outside the charset of every secret this type knows how to match. A
/// redactor that fires inside a region that a later redactor needed to match
/// whole will cut that region in half, and the later redactor then matches
/// only the first half:
///
/// ```swift
/// let text = "/Users/ana/Logs/10.0.0.5/Invoice.pdf"
///
/// // WRONG — ipv4 first splits the path, path match stops at the bracket,
/// // and the filename survives into a public issue.
/// RedactionPipeline.redact(text, with: [.ipv4, .absolutePath])
/// // "[path redacted][ip redacted]/Invoice.pdf"
///
/// // RIGHT — the path is consumed whole, IP and filename included.
/// RedactionPipeline.redact(text, with: [.absolutePath, .ipv4])
/// // "[path redacted]"
/// ```
///
/// Prefer ``recommended`` over assembling a list yourself, and append your
/// own redactors to it rather than interleaving them.
public struct DiagnosticsRedactor: Sendable {

    /// Human-readable name, surfaced in debug logs.
    public let name: String

    /// The regex matched against the blob.
    public let regex: NSRegularExpression

    /// The replacement text inserted for each match.
    public let replacement: String

    public init(name: String, regex: NSRegularExpression, replacement: String) {
        self.name = name
        self.regex = regex
        self.replacement = replacement
    }

    private static func unsafeRegex(_ pattern: String) -> NSRegularExpression {
        // Force-try here is acceptable: the patterns are compile-time constants
        // tested in PR 5. A typo would crash on package import, not in production.
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    /// Replaces email addresses with `[email redacted]`.
    public static let email = DiagnosticsRedactor(
        name: "email",
        regex: unsafeRegex(#"[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}"#),
        replacement: "[email redacted]"
    )

    /// Replaces IPv4 addresses with `[ip redacted]`.
    ///
    /// Validates each octet is 0–255. Excludes paren / dot / digit context
    /// on either side so:
    /// - a four-part build number wrapped in parens like
    ///   `App: MyApp 1.0.0 (1.0.0.123)` is left alone (the close-paren
    ///   lookahead and open-paren lookbehind both reject it);
    /// - substrings of longer numeric runs don't match.
    public static let ipv4 = DiagnosticsRedactor(
        name: "ipv4",
        regex: unsafeRegex(#"(?<![0-9.(])(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])(?:\.(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])){3}(?![0-9.)])"#),
        replacement: "[ip redacted]"
    )

    /// Replaces IPv6 addresses (including `::` zero-compression forms) with
    /// `[ip redacted]`.
    ///
    /// The lookahead requires the match to contain either at least one hex
    /// letter (real address with `A-F` digits) OR a `::` zero-compression
    /// marker (`::1`, `2001:db8::`). That excludes all-decimal colon runs
    /// like clock timestamps (`12:34:56`) which contain neither. The
    /// surrounding `(?<![A-F0-9:])` / `(?![A-F0-9:])` anchors handle
    /// addresses that start with `:` where `\b` would fail.
    public static let ipv6 = DiagnosticsRedactor(
        name: "ipv6",
        regex: unsafeRegex(#"(?<![A-F0-9:])(?=[A-F0-9:]*(?:[A-F]|::))[A-F0-9]{0,4}(?::[A-F0-9]{0,4}){2,7}(?![A-F0-9:])"#),
        replacement: "[ip redacted]"
    )

    /// Replaces `Bearer <token>` patterns with `Bearer [token redacted]`.
    public static let bearerToken = DiagnosticsRedactor(
        name: "bearerToken",
        regex: unsafeRegex(#"Bearer\s+[A-Z0-9._\-/+]{16,}"#),
        replacement: "Bearer [token redacted]"
    )

    // MARK: - Absolute path

    /// Characters a path may contain after its prefix.
    ///
    /// `\p{L}\p{M}\p{N}` matter more than they look: APFS stores filenames
    /// decomposed (NFD), so `Café.pdf` is `Cafe` + a combining acute, and
    /// without `\p{M}` the match would stop mid-filename. `\p{So}` covers
    /// emoji in filenames. Every one of these only extends how far an
    /// already-prefix-anchored match reaches, so none of them can start a
    /// false match. Space is deliberately absent — see ``absolutePath``.
    private static let pathBodyCharacters = #"A-Z0-9._~%+@$/\-\p{L}\p{M}\p{N}\p{So}"#

    /// Characters a path may *end* on: the body set minus `.` and `-`, so a
    /// path at the end of a sentence (`opened /Users/ana/x.pdf.`) or in a
    /// list doesn't swallow the punctuation that follows it.
    private static let pathTerminalCharacters = #"A-Z0-9_~%+@$/\p{L}\p{M}\p{N}\p{So}"#

    /// Characters that must NOT precede the prefix. This is what keeps URLs
    /// intact: in `https://cdn.example.com/var/x` the character before
    /// `/var` is `m`, so the match is rejected. `/` is deliberately *absent*
    /// so that `file:///Users/ana/x.pdf` still redacts — the only way a real
    /// URL path segment is preceded by `/` is a doubled slash.
    private static let pathBoundaryCharacters = #"A-Z0-9._~%@+\-\p{L}\p{M}\p{N}\p{So}"#

    /// Replaces absolute filesystem paths with `[path redacted]`, including
    /// the trailing filename.
    ///
    /// On Apple platforms a path is routinely two secrets at once: the
    /// account short name and the document name. A privacy-sensitive app
    /// filing to a public repo leaks both at once via one log line —
    /// `/Users/ana/Library/Containers/com.acme.app/Data/Documents/Return2024.pdf`
    /// publishes who the user is and what they were working on. The whole
    /// path is consumed, filename included; a redactor that stops at the last
    /// directory separator defeats the purpose.
    ///
    /// Covered prefixes: `/Users/`, `~/`, `/Volumes/`, `/private/`, `/var/`,
    /// `/tmp/`, `/Applications/`, `/Library/`.
    ///
    /// ## Deliberate non-goals
    ///
    /// - **Matching is case-insensitive** (inherited from the shared regex
    ///   options), so `/users/` and `/VAR/` match too. That is correct rather
    ///   than merely tolerable: Apple filesystems are case-insensitive by
    ///   default, so `/users/ana/taxes.pdf` is the same file and the same
    ///   leak.
    /// - **System prefixes are not covered** — `/System/`, `/usr/`, `/opt/`,
    ///   `/bin/`, `/etc/`, `/dev/`. They hold no user identity, and keeping
    ///   them readable preserves triage value: `/System/Library/Frameworks/…`
    ///   and `/usr/lib/swift/libswiftCore.dylib` in a stack trace survive
    ///   intact. Note this falls out of the boundary rule for free — the
    ///   `/Library/` inside `/System/Library/` is rejected because `m`
    ///   precedes it.
    /// - **Paths containing spaces are truncated at the space.** Space is not
    ///   a body character, because including it would let a path match run
    ///   off the end into the surrounding log message and eat the text that
    ///   makes a report triageable. The consequence is that
    ///   `/Users/ana/Documents/Tax Return.pdf` redacts to
    ///   `[path redacted] Return.pdf`. The account name — the identifying
    ///   half — is always removed; a multi-word filename may not be. Apps
    ///   whose documents routinely have spaces in their names should add a
    ///   redactor of their own *after* this one. Note that `file://` URLs are
    ///   unaffected, since they percent-encode spaces as `%20` and `%` is a
    ///   body character.
    /// - **Only POSIX separators are recognised.** A path whose separators are
    ///   backslash-escaped, as in JSON that escapes solidus
    ///   (`"\/Users\/ana\/Taxes.pdf"`), is **not** matched at all, and neither
    ///   are Windows or UNC paths. Apple's own serialisers don't escape `/`,
    ///   so this mostly affects text echoed back from a server. If your
    ///   diagnostics embed foreign JSON, redact it before handing it over.
    ///
    /// This redactor is a floor, not a guarantee. It removes the paths Apple
    /// platforms actually emit; it cannot prove a blob is free of paths. Apps
    /// with a strict disclosure obligation should treat it as one layer and
    /// still show the user the blob before submission — which the SDK does by
    /// default via ``DiagnosticsPolicy/showByDefault``.
    ///
    /// - Important: This redactor must run before ``email``, ``ipv4``, and
    ///   ``ipv6``. See the ordering hazard on ``DiagnosticsRedactor``.
    public static let absolutePath = DiagnosticsRedactor(
        name: "absolutePath",
        regex: unsafeRegex(
            #"(?<![\#(pathBoundaryCharacters)])"#                                  // not mid-URL / mid-path
            + #"(?:/Users|/Volumes|/private|/var|/tmp|/Applications|/Library|~)/"#  // anchoring prefix, `/` required
            + #"(?:[\#(pathBodyCharacters)]*[\#(pathTerminalCharacters)])?"#        // rest of path, no trailing punctuation
        ),
        replacement: "[path redacted]"
    )

    // MARK: - Recommended pipeline

    /// The vetted redactor pipeline, in an order that has been checked
    /// against the ways these patterns corrupt each other's matches.
    ///
    /// This is the default for ``DiagnosticsPolicy/redactors``. Build custom
    /// pipelines by appending to it rather than by writing a fresh array, so
    /// you inherit the ordering guarantees:
    ///
    /// ```swift
    /// policy.redactors = DiagnosticsRedactor.recommended + [myRedactor]
    /// ```
    ///
    /// The order is load-bearing: ``bearerToken`` first so IPs embedded in a
    /// JWT can't break the token match, then ``absolutePath`` so an address
    /// or email inside a path can't truncate the path match and strand the
    /// filename, then the narrower value redactors.
    public static let recommended: [DiagnosticsRedactor] = [
        .bearerToken, .absolutePath, .email, .ipv4, .ipv6,
    ]
}

// MARK: - PrivacyPolicy

/// Privacy banner copy and consent requirements shown in the report form.
public struct PrivacyPolicy: Sendable {

    /// Override the SDK's default banner copy. `nil` uses repo-visibility-specific defaults:
    /// - `.public`: "This will be posted publicly to github.com/<owner>/<repo>."
    /// - `.private`: "This will be visible to repo maintainers at github.com/<owner>/<repo>."
    public var bannerText: String?

    /// Require an explicit "I understand" checkbox before the Submit button enables.
    /// Default: `true`.
    public var requireExplicitConsent: Bool

    public init(bannerText: String? = nil, requireExplicitConsent: Bool = true) {
        self.bannerText = bannerText
        self.requireExplicitConsent = requireExplicitConsent
    }

    public static let `default` = PrivacyPolicy()
}

// MARK: - MyIssuesPolicy

/// Phase 2 — controls the "My Issues" view that lets users browse their past
/// submissions and developer replies inside the app.
public struct MyIssuesPolicy: Sendable {

    /// Whether the "My Issues" view and menu items are surfaced. Default: `true`.
    public var enabled: Bool

    /// How often the SDK polls for new replies in the background. `0` (default)
    /// means manual refresh only (pull-to-refresh on iOS, ⌘R on macOS).
    public var pollInterval: TimeInterval

    /// The label applied to submitted issues. Used to filter the issue list
    /// when displaying "My Issues." Default: `"gittickets"`.
    public var label: String

    public init(enabled: Bool = true, pollInterval: TimeInterval = 0, label: String = "gittickets") {
        self.enabled = enabled
        self.pollInterval = pollInterval
        self.label = label
    }

    public static let `default` = MyIssuesPolicy()
}
