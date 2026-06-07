//
//  IssueDetailComponents.swift
//  GitTickets — view-redesign handoff
//
//  Building blocks for `IssueDetailView`: the cached "Your report" card, the
//  first-in-thread reporter post, maintainer/visitor comment rows, and the
//  focused empty/error state card.
//

import SwiftUI

// MARK: - Markdown body
//
// EXISTING: `MarkdownCommentView` is the package's richer renderer (code
// blocks, lists, images). The redesign uses it for every body; the
// `Text(.init:)` fallback below keeps this file compiling standalone and
// already handles inline markdown (bold, code, links).

@available(macOS 13.0, iOS 16.0, *)
struct MarkdownBody: View {
    let markdown: String
    var body: some View {
        // Swap for: MarkdownCommentView(markdown: cleaned)
        Text(.init(cleaned))
            .font(.footnote)
            .lineSpacing(2)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    /// Strips the SDK's HTML correlation marker so it never shows as literal text.
    private var cleaned: String {
        markdown.replacingOccurrences(
            of: #"<!--\s*gittickets-id:[^>]*-->"#,
            with: "", options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - "Your report" card (placement: .card)

@available(macOS 13.0, iOS 16.0, *)
struct ReportCard: View {
    let report: CachedReport
    let theme: GitTicketsTheme
    @State private var showDiagnostics = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                AvatarBadge(text: "You", color: theme.resolvedAccent)
                Text("Your report").font(.footnote.weight(.semibold))
                Spacer(minLength: 0)
                Text(report.submittedAt, format: .dateTime.month().day().year())
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(theme.accentTint)

            Divider().overlay(GTSurface.hairline)

            VStack(alignment: .leading, spacing: 12) {
                MarkdownBody(markdown: report.body)
                if report.includedDiagnostics {
                    Divider().overlay(GTSurface.hairline)
                    DiagnosticsAffordance(theme: theme)
                }
            }
            .padding(14)
        }
        .cardSurface(theme: theme)
    }
}

/// The quiet "Diagnostics attached · Show" line inside the report card.
@available(macOS 13.0, iOS 16.0, *)
struct DiagnosticsAffordance: View {
    let theme: GitTicketsTheme
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "checkmark.shield").font(.caption)
            Text("Diagnostics attached").font(.caption)
            Text("·").font(.caption).foregroundStyle(.tertiary)
            Text("View on GitHub").font(.caption.weight(.semibold)).foregroundStyle(theme.resolvedAccent)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
    }
}

// MARK: - Reporter post (placement: .firstInThread)

@available(macOS 13.0, iOS 16.0, *)
struct ReporterPost: View {
    let report: CachedReport
    let theme: GitTicketsTheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AvatarBadge(text: "You", color: theme.resolvedAccent, size: 30)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text("You").font(.footnote.weight(.semibold))
                    RolePill(text: "Reporter", color: theme.resolvedAccent)
                    Spacer(minLength: 0)
                    Text(report.submittedAt, format: .relative(presentation: .named))
                        .font(.caption).foregroundStyle(.tertiary)
                }
                VStack(alignment: .leading, spacing: 12) {
                    MarkdownBody(markdown: report.body)
                    if report.includedDiagnostics {
                        Divider().overlay(GTSurface.hairline)
                        DiagnosticsAffordance(theme: theme)
                    }
                }
                .padding(14)
                .cardSurface(theme: theme)
            }
        }
    }
}

// MARK: - Comment row

@available(macOS 13.0, iOS 16.0, *)
struct CommentRow: View {
    let comment: IssueComment
    let theme: GitTicketsTheme

    private var accent: Color { comment.isMaintainer ? GTSemantic.info : .secondary }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AvatarBadge(text: initials, color: comment.isMaintainer ? GTSemantic.info : Color.secondary, size: 30)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(comment.author).font(.footnote.weight(.semibold))
                    if comment.isMaintainer { RolePill(text: "Maintainer", color: GTSemantic.info) }
                    Spacer(minLength: 0)
                    Text(comment.createdAt, format: .relative(presentation: .named))
                        .font(.caption).foregroundStyle(.tertiary)
                }
                MarkdownBody(markdown: comment.bodyMarkdown)
                    .padding(14)
                    .cardSurface(theme: theme)
            }
        }
    }

    private var initials: String {
        let parts = comment.author.split(separator: " ")
        let chars = parts.prefix(2).compactMap { $0.first }
        return String(chars).uppercased().isEmpty ? "?" : String(chars).uppercased()
    }
}

// MARK: - Small atoms

@available(macOS 13.0, iOS 16.0, *)
struct AvatarBadge: View {
    let text: String
    let color: Color
    var size: CGFloat = 26
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: size * 0.36, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(color))
    }
}

@available(macOS 13.0, iOS 16.0, *)
struct RolePill: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.4)
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.15)))
    }
}

// MARK: - Focused empty / error state card

@available(macOS 13.0, iOS 16.0, *)
struct IssueStateCard: View {

    enum Kind {
        case noReplies(issueURL: URL)
        case error(message: String, issueURL: URL)
    }

    let kind: Kind
    let theme: GitTicketsTheme
    let retry: () -> Void

    init(_ kind: Kind, theme: GitTicketsTheme, retry: @escaping () -> Void) {
        self.kind = kind
        self.theme = theme
        self.retry = retry
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(tint)
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: theme.cornerRadius + 1, style: .continuous).fill(tint.opacity(0.14)))

            Text(title).font(.headline)
            Text(message)
                .font(.footnote).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Link(destination: issueURL) {
                    Text("Open on GitHub").font(.footnote.weight(.semibold))
                }
                .buttonStyle(.bordered).controlSize(.regular).tint(.primary)

                if isError {
                    Button("Retry", action: retry)
                        .font(.footnote.weight(.semibold))
                        .buttonStyle(.borderedProminent).controlSize(.regular)
                        .tint(theme.resolvedAccent)
                }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32).padding(.horizontal, 24)
        .background(
            RoundedRectangle(cornerRadius: theme.cornerRadius + 4, style: .continuous).fill(GTSurface.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: theme.cornerRadius + 4, style: .continuous).strokeBorder(GTSurface.hairline)
        )
    }

    private var isError: Bool { if case .error = kind { return true }; return false }
    private var symbol: String { isError ? "exclamationmark.triangle" : "ellipsis.bubble" }
    private var tint: Color { isError ? GTSemantic.danger : .secondary }
    private var title: String { isError ? "Couldn't load replies" : "No replies yet" }
    private var message: String {
        switch kind {
        case .noReplies:
            return "Your report is saved above. We'll show replies here as soon as a maintainer responds."
        case .error:
            return "Your report is saved above. Replies live on GitHub — check your connection and try again."
        }
    }
    private var issueURL: URL {
        switch kind {
        case .noReplies(let url), .error(_, let url): return url
        }
    }
}
