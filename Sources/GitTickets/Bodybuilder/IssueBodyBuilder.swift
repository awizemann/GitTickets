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
            sections.append("![screenshot](\(screenshotURL.absoluteString))")
        }

        if let diagnostics, !diagnostics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append("""
            ---

            ### Diagnostics

            ```text
            \(diagnostics.trimmingCharacters(in: .whitespacesAndNewlines))
            ```
            """)
        }

        if !attachments.isEmpty {
            var rendered = "### Attachments\n"
            for attachment in attachments {
                let line = attachment.isImage
                    ? "![\(attachment.filename)](\(attachment.url.absoluteString))"
                    : "[\(attachment.filename)](\(attachment.url.absoluteString))"
                rendered += "\n" + line
            }
            sections.append(rendered)
        }

        sections.append(CorrelationMarker.render(for: report.submissionID))

        return sections.joined(separator: "\n\n")
    }
}
