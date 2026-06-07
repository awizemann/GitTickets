import SwiftUI

/// Disclosure group rendering the pre-collected, pre-redacted diagnostics blob.
///
/// `isExpanded` is bound — the parent form drives the value AND uses the same
/// binding to mark `Report.includeDiagnostics`, so collapsing the disclosure
/// also opts the user out of submitting the blob. This is the
/// "what-you-see-is-what-gets-sent" contract from PR 5: the blob in the
/// disclosure is byte-identical to what gets posted, never re-collected.
///
/// Expanded by default per ``DiagnosticsPolicy/showByDefault`` (always `true`
/// in v1 — transparency is non-negotiable).
@available(macOS 13.0, iOS 16.0, *)
public struct DiagnosticsDisclosure: View {

    @Environment(\.gitTicketsTheme) private var theme
    @Binding var isExpanded: Bool
    let text: String

    public init(isExpanded: Binding<Bool>, text: String) {
        self._isExpanded = isExpanded
        self.text = text
    }

    public var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ScrollView {
                Text(text.isEmpty ? "(no diagnostics)" : text)
                    .font(theme.monospacedFont)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 160)
            .background(
                RoundedRectangle(cornerRadius: theme.cornerRadius)
                    .fill(Color.gray.opacity(0.08))
            )
        } label: {
            Label("Diagnostics", systemImage: "stethoscope")
                .font(.callout)
        }
    }
}
