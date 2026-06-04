import Foundation

/// Embeds and extracts the opaque submission UUID in an issue body.
///
/// The marker is a standard HTML comment so it's invisible in rendered
/// markdown but recoverable from the raw body returned by the GitHub API.
/// Form: `<!-- gittickets-id: <UUID> -->`.
///
/// Phase 2's "My Issues" view uses these markers to correlate a locally
/// cached submission ID back to a GitHub issue number when the list is
/// refreshed.
enum CorrelationMarker {

    /// The marker prefix. Stable across versions — changing it would
    /// break correlation for already-shipped submissions.
    static let prefix = "<!-- gittickets-id:"

    /// The marker suffix.
    static let suffix = "-->"

    /// Renders the marker comment for the given submission UUID.
    static func render(for id: UUID) -> String {
        "\(prefix) \(id.uuidString) \(suffix)"
    }

    /// Extracts the first valid submission UUID from the given body text,
    /// or `nil` if none is present.
    ///
    /// Matches both `<!-- gittickets-id: UUID -->` and
    /// `<!--gittickets-id:UUID-->` (whitespace tolerant). Returns `nil` if
    /// the UUID portion is not a valid `UUID(uuidString:)`.
    static func extract(from body: String) -> UUID? {
        let pattern = #"<!--\s*gittickets-id:\s*([0-9a-fA-F\-]{36})\s*-->"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        guard let match = regex.firstMatch(in: body, range: range),
              match.numberOfRanges >= 2,
              let captureRange = Range(match.range(at: 1), in: body)
        else { return nil }
        return UUID(uuidString: String(body[captureRange]))
    }
}
