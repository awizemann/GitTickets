//
//  GitTicketsMyIssuesView.swift
//  GitTickets — the "My Reports" list (Phase 2 `MyIssuesPolicy`).
//
//  Lists past submissions from the local cache sorted by latest activity,
//  surfaces unread-reply badges, and pushes `IssueDetailView` on tap.
//  Refresh paths: pull-to-refresh on iOS (`.refreshable` genuinely works there),
//  plus a toolbar Refresh control, a re-fetch when the scene becomes active, and
//  optional polling — see `RefreshTriggers.swift`. The toolbar control is the
//  ONLY affordance on macOS, where `.refreshable` on a ScrollView does nothing.
//  Large title on iOS, inline on macOS.
//
//  macOS 14+ / iOS 18+. SwiftUI only.
//

import SwiftUI

public struct GitTicketsMyIssuesView: View {

    @Environment(\.gitTicketsTheme) private var envTheme

    /// Theme the view paints with. Reads from the active SDK configuration
    /// when present; falls back to the SwiftUI environment value. Same
    /// pattern as ``GitTicketsView``.
    private var theme: GitTicketsTheme {
        GitTickets.configuration?.theme ?? envTheme
    }

    /// Loads the user's submissions and reports how many were looked up, so an
    /// empty result can be told apart from a backend that matched nothing it
    /// should have. See ``MyIssuesRefresh``.
    private let loadIssues: () async throws -> MyIssuesRefresh
    /// Kind for a row's icon/tint. Defaults to the proposed cache lookup.
    private let kindFor: (UUID) -> ReportKind?
    /// Whether each issue is closed on GitHub (drives the status dot). The
    /// public `SubmittedIssue` doesn't carry state today; supply it if you
    /// have it, else everything reads "Open".
    private let isClosed: (SubmittedIssue) -> Bool
    /// Builds the detail screen for a tapped row.
    private let detail: (SubmittedIssue) -> IssueDetailView
    /// Optional "Report an issue" action (toolbar + empty-state button).
    private let onNew: (() -> Void)?

    /// Back-compat default — wires the package's singletons. Tries to refresh
    /// from the active submitter first; falls back to the cache when the
    /// network fails AND the cache has data (preferable UX to showing a
    /// `failed` card for someone who already has local rows to look at).
    public init(onNew: (() -> Void)? = nil) {
        self.init(
            loadDetailed: {
                do {
                    return try await GitTickets.refreshMyIssuesDetailed()
                } catch {
                    let cached = GitTickets.cachedSubmissions()
                    if !cached.isEmpty {
                        // Offline with local rows to show. Report requested ==
                        // returned so this never reads as a label fault.
                        return MyIssuesRefresh(issues: cached, requestedCount: cached.count)
                    }
                    throw error
                }
            },
            kindFor: { GitTickets.cachedReport(for: $0)?.kind },
            isClosed: { _ in false },
            onNew: onNew,
            detail: { IssueDetailView(issue: $0) }
        )
    }

    /// Full-control init for hosts that want to supply their own loaders /
    /// status / detail builder.
    ///
    /// - Note: A loader of this shape cannot report a shortfall, so the screen
    ///   shows the ordinary "No reports yet" state when it returns nothing. Use
    ///   the `loadDetailed:` initializer if your loader knows how many
    ///   submissions it looked up.
    public init(
        loadIssues: @escaping () async throws -> [SubmittedIssue],
        kindFor: @escaping (UUID) -> ReportKind? = { _ in nil },
        isClosed: @escaping (SubmittedIssue) -> Bool = { _ in false },
        onNew: (() -> Void)? = nil,
        detail: @escaping (SubmittedIssue) -> IssueDetailView
    ) {
        self.init(
            loadDetailed: {
                let issues = try await loadIssues()
                return MyIssuesRefresh(issues: issues, requestedCount: issues.count)
            },
            kindFor: kindFor,
            isClosed: isClosed,
            onNew: onNew,
            detail: detail
        )
    }

    /// Full-control init whose loader also reports how many submissions were
    /// looked up, letting the screen distinguish "no reports" from "we could
    /// not find your reports".
    public init(
        loadDetailed: @escaping () async throws -> MyIssuesRefresh,
        kindFor: @escaping (UUID) -> ReportKind? = { _ in nil },
        isClosed: @escaping (SubmittedIssue) -> Bool = { _ in false },
        onNew: (() -> Void)? = nil,
        detail: @escaping (SubmittedIssue) -> IssueDetailView
    ) {
        self.loadIssues = loadDetailed
        self.kindFor = kindFor
        self.isClosed = isClosed
        self.onNew = onNew
        self.detail = detail
    }

    private enum Phase: Equatable {
        case loading
        case loaded(MyIssuesRefresh)
        case failed(String)
    }
    @State private var phase: Phase = .loading

    public var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)

                case .loaded(let refresh):
                    if !refresh.issues.isEmpty {
                        list(refresh.issues, unmatched: refresh.hasPartialShortfall ? refresh.unmatchedCount : 0)
                    } else if refresh.allMissing {
                        // Cached submissions exist but the backend matched
                        // none. Saying "No reports yet" here would be a lie.
                        unmatchedState(requestedCount: refresh.requestedCount)
                    } else {
                        emptyState
                    }

                case .failed(let message):
                    failedState(message)
                }
            }
            .background(GTSurface.ground)
            .navigationTitle("My Reports")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .navigationDestination(for: SubmittedIssue.self) { detail($0) }
            .toolbar {
                if let onNew {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: onNew) { Image(systemName: "square.and.pencil") }
                            .help("Report an issue")
                    }
                }
            }
            // Inside the NavigationStack on purpose: a `.toolbar` applied to
            // the stack itself does not reach the navigation bar on iOS.
            .refreshTriggers(
                pollInterval: configuredPollInterval,
                accessibilityLabel: "Refresh reports"
            ) {
                await reload()
            }
        }
        .task { await reload() }
    }

    // MARK: List

    /// - Parameter unmatched: cached submissions that did not come back. `0`
    ///   hides the notice.
    private func list(_ issues: [SubmittedIssue], unmatched: Int) -> some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if unmatched > 0 {
                    unmatchedNotice(count: unmatched)
                }
                ForEach(sorted(issues)) { issue in
                    NavigationLink(value: issue) {
                        MyReportRow(issue: issue, kind: kindFor(issue.id), closed: isClosed(issue), theme: theme)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await reload() }
    }

    /// Most recent activity first (latest reply, else creation date).
    private func sorted(_ issues: [SubmittedIssue]) -> [SubmittedIssue] {
        issues.sorted { a, b in
            (a.latestReplyAt ?? a.createdAt) > (b.latestReplyAt ?? b.createdAt)
        }
    }

    // MARK: States

    /// Inline notice for a *partial* shortfall — some reports came back, some
    /// did not.
    ///
    /// Deliberately not the full-screen ``unmatchedState``: losing one report
    /// out of twenty does not justify taking over the screen, and a deleted
    /// issue produces this legitimately. But silence was worse — a report that
    /// lost its label looked exactly like one that was never filed, which is
    /// the same failure the full-screen state exists to prevent, only quieter.
    ///
    /// Same wording constraint as ``unmatchedState``: "isn't showing up" is
    /// true whether the issue was deleted or merely lost its label, and the SDK
    /// cannot tell those apart.
    private func unmatchedNotice(count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.orange)
            Text(
                count == 1
                    ? "1 earlier report isn't showing up."
                    : "\(count) earlier reports aren't showing up."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }

    /// Shown when this device has filed reports but the backend returned none
    /// of them.
    ///
    /// The wording must not name a cause, because the SDK cannot know one. The
    /// backend finds issues by label, so an issue is absent from the result
    /// whether it was **deleted** or merely **lost its label** — those are
    /// indistinguishable from here, and they call for opposite reassurances.
    /// An earlier version of this screen promised "they haven't been lost",
    /// which is plainly false for someone whose reports really were deleted.
    ///
    /// So: state what is known (you filed N, none came back), offer both
    /// plausible explanations, and do not imply the situation is temporary.
    /// Labels and permissions are never mentioned — they mean nothing to the
    /// person reading this; that detail goes to the logger instead.
    private func unmatchedState(requestedCount: Int) -> some View {
        VStack(spacing: 12) {
            stateIcon("questionmark.folder", tint: .orange)
            Text("Your reports aren't showing up").font(.headline)
            Text(
                requestedCount == 1
                    ? "You've filed 1 report, but it didn't come back. It may have been removed, or there may be a problem reaching the issue tracker."
                    : "You've filed \(requestedCount) reports, but none of them came back. They may have been removed, or there may be a problem reaching the issue tracker."
            )
            .font(.footnote).foregroundStyle(.secondary)
            .multilineTextAlignment(.center).frame(maxWidth: 300)
            .fixedSize(horizontal: false, vertical: true)
            Text("If you were expecting to see them, contact support.")
                .font(.caption).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center).frame(maxWidth: 300)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            stateIcon("tray", tint: .secondary)
            Text("No reports yet").font(.headline)
            Text("When you file an issue, it shows up here so you can track replies from the team.")
                .font(.footnote).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 300)
                .fixedSize(horizontal: false, vertical: true)
            if let onNew {
                Button(action: onNew) {
                    Label("Report an issue", systemImage: "square.and.pencil").fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).tint(theme.resolvedAccent)
                .padding(.top, 2)
            }
        }
        .padding(32)
        .frame(maxWidth: 420)
        .background(RoundedRectangle(cornerRadius: theme.cornerRadius + 4, style: .continuous).fill(GTSurface.card))
        .overlay(RoundedRectangle(cornerRadius: theme.cornerRadius + 4, style: .continuous).strokeBorder(GTSurface.hairline))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    private func failedState(_ message: String) -> some View {
        VStack(spacing: 12) {
            stateIcon("exclamationmark.triangle", tint: GTSemantic.danger)
            Text("Couldn't load your reports").font(.headline)
            Text(message).font(.footnote).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 300)
            Button("Retry") { Task { await reload() } }
                .buttonStyle(.borderedProminent).controlSize(.large).tint(theme.resolvedAccent)
                .padding(.top, 2)
        }
        .padding(32)
        .frame(maxWidth: 420)
        .background(RoundedRectangle(cornerRadius: theme.cornerRadius + 4, style: .continuous).fill(GTSurface.card))
        .overlay(RoundedRectangle(cornerRadius: theme.cornerRadius + 4, style: .continuous).strokeBorder(GTSurface.hairline))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    private func stateIcon(_ symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 24))
            .foregroundStyle(tint)
            .frame(width: 52, height: 52)
            .background(RoundedRectangle(cornerRadius: theme.cornerRadius + 1, style: .continuous).fill(tint.opacity(0.14)))
    }

    private func reload() async {
        // Only blank the screen for the FIRST load. 2.2.0 added three more
        // refresh triggers (toolbar, scene reactivation, polling) that all land
        // here — unconditionally dropping to `.loading` would replace a
        // perfectly good list with a spinner on every one of them, and with
        // polling enabled it would flicker on an interval.
        if case .loaded = phase {} else { phase = .loading }
        do { phase = .loaded(try await loadIssues()) }
        catch { phase = .failed((error as? GitTicketsError)?.description ?? error.localizedDescription) }
    }
}

// MARK: - Row

struct MyReportRow: View {
    let issue: SubmittedIssue
    let kind: ReportKind?
    let closed: Bool
    let theme: GitTicketsTheme

    private var unread: Int { issue.unreadReplyCount }

    var body: some View {
        HStack(spacing: 12) {
            // Kind icon tile (falls back to a neutral dot if kind unknown)
            Image(systemName: kind?.symbol ?? "circle.dashed")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(kind?.badgeColor ?? .secondary)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill((kind?.badgeColor ?? .secondary).opacity(0.14)))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    if unread > 0 {
                        Circle().fill(theme.resolvedAccent).frame(width: 7, height: 7)
                    }
                    Text(issue.title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text("#\(issue.issueNumber)").font(.system(.caption, design: .monospaced)).foregroundStyle(.tertiary)
                    Text("·").foregroundStyle(.tertiary)
                    Label(closed ? "Closed" : "Open", systemImage: "circle.fill")
                        .labelStyle(StatusDotLabelStyle(color: closed ? Color.secondary : GTSemantic.success))
                }
                .font(.caption).foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 5) {
                if unread > 0 {
                    Text("\(unread) NEW")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(theme.onAccentColor)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(theme.resolvedAccent))
                }
                Text(activity, format: .relative(presentation: .named))
                    .font(.caption).foregroundStyle(.tertiary)
            }
            #if os(iOS)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            #endif
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: theme.cornerRadius + 1, style: .continuous).fill(GTSurface.card))
        .overlay(RoundedRectangle(cornerRadius: theme.cornerRadius + 1, style: .continuous).strokeBorder(GTSurface.hairline))
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
        .contentShape(Rectangle())
    }

    private var activity: Date { issue.latestReplyAt ?? issue.createdAt }
}

/// Tiny colored status dot + label, used for Open/Closed.
///
/// The label-style configuration is referenced as
/// ``LabelStyleConfiguration`` (the fully-qualified system type) rather than
/// the unqualified ``Configuration`` associated-type alias, because the
/// package has its own public ``Configuration`` type and Swift's namespace
/// lookup resolves the bare name to that one first.
struct StatusDotLabelStyle: LabelStyle {
    let color: Color
    func makeBody(configuration: LabelStyleConfiguration) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            configuration.title
        }
    }
}

// MARK: - on-accent helper

extension GitTicketsTheme {
    /// White reads correctly on every reasonable accent; exposed so the row's
    /// "N NEW" pill doesn't hard-code a literal.
    var onAccentColor: Color { .white }
}
