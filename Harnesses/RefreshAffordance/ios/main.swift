import SwiftUI
import UIKit

// iOS side of the refresh-affordance question. Two independent checks, both run
// automatically and reported on screen and to stdout — no gestures or taps
// needed, which is what makes this runnable without input injection.
//
//   CHECK 1 — UIRefreshControl. `.refreshable` on a bare ScrollView: does iOS
//     install one? (The macOS equivalent installs nothing. iOS differs — this
//     is the check that corrected the original assumption.)
//
//   CHECK 2 — toolbar button. A `.toolbar` placed INSIDE a NavigationStack,
//     mirroring how GitTicketsMyIssuesView attaches its Refresh control: does
//     it reach the navigation bar? A `.toolbar` applied to the NavigationStack
//     from the OUTSIDE does not, which is why placement matters and why this
//     check exists.
//
// Run via ./run-ios-harness.sh with a booted simulator.

@main
struct RefreshHarnessApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
    }
}

struct Finding: Identifiable {
    enum Status {
        case pass, fail, visual

        var text: String {
            switch self {
            case .pass: "YES"
            case .fail: "NO"
            case .visual: "LOOK"
            }
        }

        var tint: Color {
            switch self {
            case .pass: .green
            case .fail: .red
            case .visual: .orange
            }
        }
    }

    let id = UUID()
    let label: String
    let status: Status
    let detail: String
}

struct RootView: View {
    @State private var findings: [Finding] = []

    var body: some View {
        VStack(spacing: 4) {
            Text("iOS refresh affordance").font(.headline)
            ForEach(findings) { f in
                HStack(alignment: .top, spacing: 6) {
                    Text(f.status.text)
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundStyle(f.status.tint)
                        .frame(width: 42, alignment: .leading)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(f.label).font(.system(size: 11, weight: .semibold))
                        Text(f.detail)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 8)

            // Mirrors GitTicketsMyIssuesView: ScrollView + .refreshable, with
            // the toolbar INSIDE the NavigationStack.
            NavigationStack {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(0..<12, id: \.self) { i in
                            Text("row \(i)")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(4)
                                .background(Color.blue.opacity(0.12))
                        }
                    }
                    .padding(6)
                }
                .refreshable { }
                .navigationTitle("Inside")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        Button { } label: { Image(systemName: "arrow.clockwise") }
                            .accessibilityLabel("Refresh reports")
                    }
                }
            }
            .border(Color.blue)
        }
        .task {
            try? await Task.sleep(for: .seconds(2))
            findings = scan()
            for f in findings {
                print("SCAN \(f.status.text) \(f.label) — \(f.detail)")
            }
        }
    }
}

@MainActor
func scan() -> [Finding] {
    let windows = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap(\.windows)

    var scrollViews: [(String, Bool)] = []
    var navBarControls: [String] = []
    for window in windows {
        walk(window, scrollViews: &scrollViews, navBarControls: &navBarControls)
    }

    let withControl = scrollViews.filter { $0.1 }

    // A SwiftUI toolbar button is NOT reliably detectable from inside the
    // process. Three methods were tried and all three are recorded here so
    // nobody burns the time again:
    //   1. `UIView.accessibilityLabel` over the view tree — false NEGATIVE.
    //      SwiftUI serves accessibility from its own engine and never stamps
    //      the label onto the backing UIView.
    //   2. Any `UIControl` inside the `UINavigationBar` — false POSITIVE. It
    //      matches `_UINavigationBarTitleControl`, i.e. the title, whether or
    //      not a button exists.
    //   3. Walking `accessibilityElements` — false NEGATIVE. SwiftUI builds
    //      those lazily when an assistive client asks, so an in-process walk
    //      sees nothing.
    // The screenshot is therefore the evidence for CHECK2. It is still kept
    // below in case a future OS starts publishing the label eagerly.
    var axLabels: [String] = []
    for window in windows {
        collectAXLabels(window, into: &axLabels)
    }
    let refreshButtons = axLabels.filter { $0.localizedCaseInsensitiveContains("refresh") }

    return [
        Finding(
            label: "CHECK1 ScrollView + .refreshable installs UIRefreshControl",
            status: withControl.isEmpty ? .fail : .pass,
            detail: "\(withControl.count)/\(scrollViews.count) scrollviews: "
                + scrollViews.map { "\($0.0)=\($0.1 ? "Y" : "N")" }.joined(separator: " ")
        ),
        // Not auto-detectable in-process — see the note in `scan()`. The
        // screenshot is the evidence, and it is unambiguous: the button either
        // renders in the nav bar or it does not.
        Finding(
            label: "CHECK2 toolbar inside NavigationStack — CONFIRM VISUALLY",
            status: .visual,
            detail: "expect a ⟳ button at the trailing edge of the 'Inside' bar"
                + (refreshButtons.isEmpty ? "" : " (ax also saw: \(refreshButtons.joined(separator: ", ")))")
        ),
    ]
}

@MainActor
private func walk(_ view: UIView, scrollViews: inout [(String, Bool)], navBarControls: inout [String]) {
    if let scroll = view as? UIScrollView {
        scrollViews.append((String(describing: type(of: scroll)), scroll.refreshControl != nil))
    }
    if let navBar = view as? UINavigationBar {
        collectControls(navBar, into: &navBarControls)
    }
    for sub in view.subviews {
        walk(sub, scrollViews: &scrollViews, navBarControls: &navBarControls)
    }
}

@MainActor
private func collectControls(_ view: UIView, into out: inout [String]) {
    if view is UIControl {
        out.append(String(describing: type(of: view)))
    }
    for sub in view.subviews { collectControls(sub, into: &out) }
}

/// Walks the accessibility element tree — what VoiceOver traverses — rather
/// than the raw view tree, following both `accessibilityElements` and
/// `subviews` since SwiftUI mixes the two.
@MainActor
private func collectAXLabels(_ object: Any, into out: inout [String], depth: Int = 0) {
    guard depth < 16 else { return }
    if let ns = object as? NSObject {
        if let label = ns.accessibilityLabel, !label.isEmpty {
            out.append(label)
        }
        if let elements = ns.accessibilityElements {
            for element in elements {
                collectAXLabels(element, into: &out, depth: depth + 1)
            }
        }
    }
    if let view = object as? UIView {
        for sub in view.subviews {
            collectAXLabels(sub, into: &out, depth: depth + 1)
        }
    }
}
