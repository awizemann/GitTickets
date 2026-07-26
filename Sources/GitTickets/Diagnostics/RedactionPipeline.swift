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
///
/// ## The caller's order is honoured verbatim
///
/// Order affects correctness, not just efficiency: because every replacement
/// inserts brackets and spaces, a redactor running too early can split a
/// region that a later redactor needed to match whole, and the later redactor
/// then matches only the head. See the ordering hazard documented on
/// ``DiagnosticsRedactor``; ``DiagnosticsRedactor/recommended`` is the order
/// that survives it.
///
/// This type nevertheless applies the array exactly as supplied and does
/// **not** sort or reorder it. That is a deliberate decision, not an
/// oversight: the array is the caller's contract, adopters legitimately
/// depend on specific positions (a custom redactor that must see raw text, or
/// must see post-redaction text), and silently rearranging it would trade a
/// documented hazard for an invisible one. Fix bad ordering at the call site.
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
