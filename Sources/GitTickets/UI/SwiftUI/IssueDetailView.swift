//
//  IssueDetailView.swift
//  GitTickets — redesigned detail screen, opened from "My Reports".
//
//  Three problems fixed versus the old layout:
//    1. The user's ORIGINAL report (cached locally) is now shown — the screen
//       is never just a header over a void.
//    2. Empty / error states are a focused, centered card pinned beneath the
//       cached report, not a banner floating in empty space.
//    3. Hierarchy reads: kind + status → title → meta → your report → replies.
//
//  Lives inside a NavigationStack on both platforms (large title on iOS,
//  inline on macOS). macOS 13+ / iOS 16+.
//
//  `CachedReport` + `IssueComment` are public model types defined in
//  `PublicAPI/Models.swift`.
//

import SwiftUI

@available(macOS 13.0, iOS 16.0, *)
public struct IssueDetailView: View {

    /// Where the original report sits. Locked to `.card` (Option 1) — a
    /// distinct "Your report" card above the thread. See design reference §2.
    public enum ReportPlacement { case card, firstInThread }
    private let placement: ReportPlacement = .card

    @Environment(\.gitTicketsTheme) private var envTheme

    private let issue: SubmittedIssue
    private let cachedReport: CachedReport?
    private let loadComments: () async throws -> [IssueComment]

    /// Theme the view paints with. Reads from the active SDK configuration
    /// when present; falls back to the SwiftUI environment value. Same
    /// pattern as ``GitTicketsView`` / ``GitTicketsMyIssuesView``.
    private var theme: GitTicketsTheme {
        GitTickets.configuration?.theme ?? envTheme
    }

    public init(
        issue: SubmittedIssue,
        cachedReport: CachedReport?,
        loadComments: @escaping () async throws -> [IssueComment]
    ) {
        self.issue = issue
        self.cachedReport = cachedReport
        self.loadComments = loadComments
    }

    /// Backward-compat convenience matching the v1.0 init shape. Reads the
    /// cached report through ``GitTickets/cachedReport(for:)`` and the
    /// comments through ``GitTickets/fetchComments(issueNumber:)``.
    public init(issue: SubmittedIssue) {
        self.init(
            issue: issue,
            cachedReport: GitTickets.cachedReport(for: issue.id),
            loadComments: {
                try await GitTickets.fetchComments(issueNumber: issue.issueNumber)
            }
        )
    }

    private enum Phase: Equatable {
        case loading
        case loaded([IssueComment])
        case failed(String)
    }
    @State private var phase: Phase = .loading

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                IssueHeader(issue: issue, kind: cachedReport?.kind, theme: theme)

                if placement == .card, let report = cachedReport {
                    ReportCard(report: report, theme: theme)
                }

                threadOrState
            }
            .padding(20)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(GTSurface.ground)
        .navigationTitle("Issue #\(issue.issueNumber)")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await reload() }
        .refreshable { await reload() }
    }

    @ViewBuilder private var threadOrState: some View {
        switch phase {
        case .loading:
            HStack { Spacer(); ProgressView(); Spacer() }
                .padding(.vertical, 32)

        case .loaded(let comments):
            if comments.isEmpty && placement == .card {
                IssueStateCard(.noReplies(issueURL: issue.issueURL), theme: theme, retry: { Task { await reload() } })
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    threadLabel(count: comments.count)
                    // Option 2: original report leads the thread as the first post.
                    if placement == .firstInThread, let report = cachedReport {
                        ReporterPost(report: report, theme: theme)
                    }
                    ForEach(comments) { comment in
                        CommentRow(comment: comment, theme: theme)
                    }
                }
            }

        case .failed(let message):
            IssueStateCard(.error(message: message, issueURL: issue.issueURL),
                           theme: theme,
                           retry: { Task { await reload() } })
        }
    }

    private func threadLabel(count: Int) -> some View {
        HStack(spacing: 8) {
            Text(placement == .firstInThread ? "Conversation" : "Replies")
                .font(.footnote.weight(.semibold))
            if placement != .firstInThread {
                Text("\(count)").font(.system(.caption, design: .monospaced)).foregroundStyle(.tertiary)
            }
            Rectangle().fill(GTSurface.hairline).frame(height: 1)
        }
    }

    private func reload() async {
        // Mark replies read when the user opens detail — the parent list's
        // unread badge clears immediately, before the network load even
        // completes, so list updates feel responsive.
        GitTickets.markRepliesRead(submissionID: issue.id, count: issue.replyCount)
        phase = .loading
        do { phase = .loaded(try await loadComments()) }
        catch { phase = .failed(error.localizedDescription) }
    }
}

// MARK: - Issue header

@available(macOS 13.0, iOS 16.0, *)
struct IssueHeader: View {
    let issue: SubmittedIssue
    let kind: ReportKind?
    let theme: GitTicketsTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if let kind { KindBadge(kind: kind) }
                StatusBadge()
                Spacer(minLength: 0)
                Text("#\(issue.issueNumber)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            Text(issue.title)
                .font(.title2.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 7) {
                Text("Filed \(issue.createdAt, format: .dateTime.month().day().year())")
                if issue.replyCount > 0 {
                    dot
                    Text("^[\(issue.replyCount) reply](inflect: true)")
                }
                if let latest = issue.latestReplyAt {
                    dot
                    Text("last reply \(latest, format: .relative(presentation: .named))")
                }
            }
            .font(.caption).foregroundStyle(.secondary)

            Link(destination: issue.issueURL) {
                Label("Open on GitHub", systemImage: "arrow.up.right.square")
                    .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .tint(.primary)
        }
    }

    private var dot: some View {
        Circle().fill(.tertiary).frame(width: 3, height: 3)
    }
}

@available(macOS 13.0, iOS 16.0, *)
struct KindBadge: View {
    let kind: ReportKind
    var body: some View {
        Label(kind.displayTitle, systemImage: kind.symbol)
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .foregroundStyle(kind.badgeColor)
            .background(Capsule().fill(kind.badgeColor.opacity(0.14)))
    }
}

@available(macOS 13.0, iOS 16.0, *)
struct StatusBadge: View {
    var body: some View {
        Label("Open", systemImage: "circle")
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .foregroundStyle(GTSemantic.success)
            .background(Capsule().fill(GTSemantic.success.opacity(0.14)))
    }
}
