import SwiftUI

/// Renders one ``IssueComment``: author header, relative timestamp, and the
/// body markdown rendered through `AttributedString(markdown:)`.
///
/// Falls back to plain `Text(comment.body)` when the body fails to parse as
/// markdown — better to show the raw text than to silently drop a comment
/// whose body contains an unexpected token.
@available(macOS 13.0, iOS 16.0, *)
public struct MarkdownCommentView: View {

    @Environment(\.gitTicketsTheme) private var theme
    let comment: IssueComment

    public init(comment: IssueComment) {
        self.comment = comment
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(comment.author.isEmpty ? "Reply" : "@" + comment.author)
                    .font(.callout.weight(.semibold))
                Text(comment.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            body(for: comment.body)
                .font(theme.bodyFont)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: theme.cornerRadius)
                .fill(Color.gray.opacity(0.08))
        )
    }

    /// Parses the markdown via `AttributedString(markdown:)`. The "inline-only"
    /// parse option is the right default for issue comments — GitHub renders
    /// block elements but most comments are paragraphs of text + inline links;
    /// allowing block elements lets a stray `# Header` line eat the rest of
    /// the comment as a heading. Adopters who need full block rendering can
    /// reach for a real markdown library; the SDK stays small.
    @ViewBuilder private func body(for source: String) -> some View {
        if let attributed = try? AttributedString(
            markdown: source,
            options: AttributedString.MarkdownParsingOptions(
                allowsExtendedAttributes: false,
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            Text(attributed)
        } else {
            Text(source)
        }
    }
}
