import Foundation

/// Per-``ReportKind`` starter bodies the form pre-fills before the user types.
///
/// The intent is "give the user a structure to fill in" not "force them
/// through a form." Each template is a few markdown headers with empty
/// space between them; the user can replace any of it.
enum BodyTemplates {

    /// Returns the starter body for the given kind.
    static func starter(for kind: ReportKind) -> String {
        switch kind {
        case .bug:
            return """
            ### What happened?


            ### What did you expect to happen?


            ### Steps to reproduce
            1.\u{0020}
            2.\u{0020}
            3.\u{0020}
            """
        case .featureRequest:
            return """
            ### Problem to solve


            ### Proposed solution


            ### Alternatives considered

            """
        case .question:
            return """
            ### Your question

            """
        }
    }

    /// Returns the default GitHub labels to apply for the given kind.
    ///
    /// All submissions get the `gittickets` label too — that's applied by
    /// the relay / submitter, not the template.
    static func defaultLabels(for kind: ReportKind) -> [String] {
        switch kind {
        case .bug: return ["bug"]
        case .featureRequest: return ["enhancement"]
        case .question: return ["question"]
        }
    }
}
