//
//  GitTicketsMyIssuesView.swift
//  GitTickets — view-redesign handoff
//
//  The "My Reports" list (Phase 2 `MyIssuesPolicy`). Lists past submissions
//  from the local cache sorted by latest activity, surfaces unread-reply
//  badges, and pushes `IssueDetailView` on tap. Pull-to-refresh on iOS,
//  ⌘R on macOS. Large title on iOS, inline on macOS.
//
//  macOS 13+ / iOS 16+. SwiftUI only.
//

import SwiftUI

@available(macOS 13.0, iOS 16.0, *)
public struct GitTicketsMyIssuesView: View {

    @Environment(\.gitTicketsTheme) private var theme

    /// Loads the user's submissions (typically `GitTickets.cachedSubmissions()`,
    /// optionally refreshed against the relay first).
    private let loadIssues: () async throws -> [SubmittedIssue]
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

    public init(
        loadIssues: @escaping () async throws -> [SubmittedIssue],
        kindFor: @escaping (UUID) -> ReportKind? = { _ in nil },
        isClosed: @escaping (SubmittedIssue) -> Bool = { _ in false },
        onNew: (() -> Void)? = nil,
        detail: @escaping (SubmittedIssue) -> IssueDetailView
    ) {
        self.loadIssues = loadIssues
        self.kindFor = kindFor
        self.isClosed = isClosed
        self.onNew = onNew
        self.detail = detail
    }

    private enum Phase: Equatable {
        case loading
        case loaded([SubmittedIssue])
        case failed(String)
    }
    @State private var phase: Phase = .loading

    public var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)

                case .loaded(let issues):
                    if issues.isEmpty {
                        emptyState
                    } else {
                        list(issues)
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
        }
        .task { await reload() }
    }

    // MARK: List

    private func list(_ issues: [SubmittedIssue]) -> some View {
        ScrollView {
            LazyVStack(spacing: 8) {
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
        do { phase = .loaded(try await loadIssues()) }
        catch { phase = .failed(error.localizedDescription) }
    }
}

// MARK: - Row

@available(macOS 13.0, iOS 16.0, *)
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
@available(macOS 13.0, iOS 16.0, *)
struct StatusDotLabelStyle: LabelStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            configuration.title
        }
    }
}

// MARK: - on-accent helper

@available(macOS 13.0, iOS 16.0, *)
extension GitTicketsTheme {
    /// White reads correctly on every reasonable accent; exposed so the row's
    /// "N NEW" pill doesn't hard-code a literal.
    var onAccentColor: Color { .white }
}
