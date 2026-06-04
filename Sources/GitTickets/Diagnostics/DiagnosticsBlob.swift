import Foundation

/// The user-visible diagnostics block that gets shown in the report form
/// (expanded by default) and inlined into the GitHub issue body verbatim.
///
/// Carries both the rendered markdown-friendly text and the structured
/// key/value sections it was built from, for tests and any future
/// programmatic introspection.
struct DiagnosticsBlob: Sendable, Hashable {

    /// The redacted, plain-text blob ready to drop into the issue body.
    /// Empty when no fields are enabled by the policy.
    let text: String

    /// Pre-redaction structured field map (key → value). Used by tests and
    /// debug logging; the user-facing form renders ``text``.
    let sections: [(key: String, value: String)]

    init(text: String, sections: [(key: String, value: String)]) {
        self.text = text
        self.sections = sections
    }

    static func == (lhs: DiagnosticsBlob, rhs: DiagnosticsBlob) -> Bool {
        guard lhs.text == rhs.text else { return false }
        guard lhs.sections.count == rhs.sections.count else { return false }
        for (l, r) in zip(lhs.sections, rhs.sections) where l != r {
            return false
        }
        return true
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(text)
        for (key, value) in sections {
            hasher.combine(key)
            hasher.combine(value)
        }
    }
}
