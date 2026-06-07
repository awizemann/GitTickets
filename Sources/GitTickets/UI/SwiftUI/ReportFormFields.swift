import SwiftUI

/// Kind picker + title field + description editor. The three fields that
/// drive the body of the report. Extracted from ``GitTicketsView`` so adopters
/// can compose their own form chrome while keeping the canonical input shape.
@available(macOS 13.0, iOS 16.0, *)
struct ReportFormFields: View {

    @Environment(\.gitTicketsTheme) private var theme
    @Binding var kind: ReportKind
    @Binding var title: String
    @Binding var bodyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Kind", selection: $kind) {
                Text("Bug").tag(ReportKind.bug)
                Text("Feature request").tag(ReportKind.featureRequest)
                Text("Question").tag(ReportKind.question)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Report kind")

            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)
                .font(theme.bodyFont)
                .accessibilityLabel("Issue title")

            VStack(alignment: .leading, spacing: 6) {
                Text("Describe the problem")
                    .font(.callout.weight(.medium))
                TextEditor(text: $bodyText)
                    .font(theme.bodyFont)
                    .frame(minHeight: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: theme.cornerRadius)
                            .strokeBorder(Color.secondary.opacity(0.3))
                    )
                    .accessibilityLabel("Issue description")
            }
        }
    }
}
