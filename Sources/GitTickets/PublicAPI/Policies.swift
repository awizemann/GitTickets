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
    /// Default: `[.bearerToken, .email, .ipv4, .ipv6]`. Bearer tokens run
    /// first so that IPv4/IPv6 redactions inside a token don't corrupt the
    /// token's surrounding charset and let the leftover halves leak.
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
        redactors: [DiagnosticsRedactor] = [.bearerToken, .email, .ipv4, .ipv6],
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
