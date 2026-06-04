import Foundation

/// Top-level configuration passed to ``GitTickets/configure(_:)``.
///
/// Bundles the repo coordinates, auth mode, theme, and the three behavior
/// policies (diagnostics, privacy, my-issues). Most fields have sensible
/// defaults — at minimum supply ``repo`` and ``auth``.
public struct Configuration: Sendable {

    /// Where submissions land.
    public let repo: RepoCoordinate

    /// How the SDK authenticates to GitHub.
    public let auth: AuthMode

    /// Visual styling. Defaults to ``GitTicketsTheme/default``, which inherits
    /// the host app's `Color.accentColor` and uses system fonts.
    public let theme: GitTicketsTheme

    /// Diagnostics collection + redaction policy.
    public let diagnostics: DiagnosticsPolicy

    /// Privacy banner copy and consent requirements.
    public let privacy: PrivacyPolicy

    /// Phase 2 "My Issues" behavior — list visibility, refresh cadence, label.
    public let myIssues: MyIssuesPolicy

    /// Optional callback for SDK log lines.
    public let logger: GitTicketsLogger?

    /// Memberwise initializer with defaults for everything except ``repo`` and ``auth``.
    public init(
        repo: RepoCoordinate,
        auth: AuthMode,
        theme: GitTicketsTheme = .default,
        diagnostics: DiagnosticsPolicy = .default,
        privacy: PrivacyPolicy = .default,
        myIssues: MyIssuesPolicy = .default,
        logger: GitTicketsLogger? = nil
    ) {
        self.repo = repo
        self.auth = auth
        self.theme = theme
        self.diagnostics = diagnostics
        self.privacy = privacy
        self.myIssues = myIssues
        self.logger = logger
    }
}
