import Foundation

/// Applies a sequence of ``DiagnosticsRedactor`` substitutions to text.
///
/// Redactors run in declaration order. Each redactor's regex is matched
/// against the (already-redacted-by-earlier-redactors) text and every match
/// is replaced with its replacement template.
///
/// The output the user sees in the form is byte-identical to what gets
/// POSTed — the pipeline is run once before display and that string is
/// what's submitted. This is the critical invariant.
enum RedactionPipeline {

    /// Returns `text` with each redactor applied in order. Throws nothing
    /// because every default redactor uses a compile-time-valid regex; a
    /// caller-supplied redactor that misbehaves is treated as a no-op match.
    static func redact(_ text: String, with redactors: [DiagnosticsRedactor]) -> String {
        var current = text
        for redactor in redactors {
            let range = NSRange(current.startIndex..<current.endIndex, in: current)
            current = redactor.regex.stringByReplacingMatches(
                in: current,
                options: [],
                range: range,
                withTemplate: redactor.replacement
            )
        }
        return current
    }
}
