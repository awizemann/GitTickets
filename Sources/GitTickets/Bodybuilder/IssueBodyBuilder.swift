import Foundation

/// An attachment that has been uploaded to the relay and is ready to be
/// inlined into the issue body as a markdown image (or link, for non-images).
struct UploadedAttachment: Sendable, Hashable {

    /// Filename surfaced as the markdown link text.
    let filename: String

    /// Public URL the relay returned for the uploaded blob.
    let url: URL

    /// MIME type. `image/*` types render as inline `![]()` images; other
    /// types render as `[]()` links.
    let mimeType: String

    var isImage: Bool { mimeType.lowercased().hasPrefix("image/") }
}

/// Assembles the final markdown body that gets POSTed to GitHub.
///
/// Structure:
///
/// ```
/// [user body text]
///
/// ![screenshot](screenshot-url)
///
/// ---
///
/// ### Diagnostics
///
/// ```text
/// OS: ...
/// App: ...
/// ```
///
/// ### Attachments
///
/// ![file1.png](url1)
/// [file2.log](url2)
///
/// <!-- gittickets-id: UUID -->
/// ```
///
/// Sections are omitted when empty. The correlation marker is always last
/// so the regex extractor doesn't trip on stray HTML comments earlier in
/// the body.
enum IssueBodyBuilder {

    /// Builds the markdown body for the given report and supporting data.
    ///
    /// - Parameters:
    ///   - report: The user-authored report.
    ///   - diagnostics: The pre-redacted diagnostics blob. `nil` or empty
    ///     suppresses the Diagnostics section.
    ///   - screenshotURL: URL returned by the relay's attachment endpoint
    ///     for the optional screenshot. `nil` suppresses the inline image.
    ///   - attachments: URLs returned by the relay for additional attachments.
    /// - Returns: The full markdown body ready to POST.
    static func build(
        report: Report,
        diagnostics: String?,
        screenshotURL: URL?,
        attachments: [UploadedAttachment]
    ) -> String {
        var sections: [String] = []

        let trimmedBody = report.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBody.isEmpty {
            sections.append(trimmedBody)
        }

        if let screenshotURL {
            sections.append("![screenshot](\(escapeURLForMarkdown(screenshotURL)))")
        }

        if let diagnostics, !diagnostics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let trimmedDiagnostics = diagnostics.trimmingCharacters(in: .whitespacesAndNewlines)
            // Choose a fence longer than the longest run of backticks
            // anywhere inside the body so the inner content can't close the
            // fence prematurely (a single ``` in a log line would otherwise
            // collapse the block and let later content render as prose).
            let fence = fenceFor(trimmedDiagnostics)
            sections.append("""
            ---

            ### Diagnostics

            \(fence)text
            \(trimmedDiagnostics)
            \(fence)
            """)
        }

        if !attachments.isEmpty {
            var rendered = "### Attachments\n"
            for attachment in attachments {
                let safeURL = escapeURLForMarkdown(attachment.url)
                let safeName = escapeMarkdownLinkText(attachment.filename)
                let line = attachment.isImage
                    ? "![\(safeName)](\(safeURL))"
                    : "[\(safeName)](\(safeURL))"
                rendered += "\n" + line
            }
            sections.append(rendered)
        }

        sections.append(CorrelationMarker.render(for: report.submissionID))

        return sections.joined(separator: "\n\n")
    }

    /// Picks a fence longer than any run of backticks inside `content`.
    /// GFM closes a fenced code block on the first run of the same length
    /// or longer, so the outer fence must always be strictly longer.
    static func fenceFor(_ content: String) -> String {
        var longest = 0
        var current = 0
        for ch in content {
            if ch == "`" {
                current += 1
                if current > longest { longest = current }
            } else {
                current = 0
            }
        }
        let length = max(3, longest + 1)
        return String(repeating: "`", count: length)
    }

    /// Percent-encodes `(` and `)` so a URL whose query/path contains a
    /// literal close-paren doesn't terminate the markdown link early.
    static func escapeURLForMarkdown(_ url: URL) -> String {
        url.absoluteString
            .replacingOccurrences(of: "(", with: "%28")
            .replacingOccurrences(of: ")", with: "%29")
    }

    /// Escapes `[`, `]`, and `\` inside a markdown link's display text so
    /// a filename like `weird]name.png` doesn't break the link grammar.
    static func escapeMarkdownLinkText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }
}
