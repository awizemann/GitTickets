import SwiftUI
import AppKit
import GitTickets

// Hosts the REAL GitTicketsMyIssuesView on macOS and reports every refresh
// affordance it can find. Findings then rest on shipped SDK code rather than on
// a reconstruction of it.
//
// Two independent checks:
//
//   1. SCROLLVIEW — is there a PlatformRefreshControlProxy on the backing
//      scroll view? This is what `.refreshable` installs on macOS for a List.
//      For a ScrollView it is absent, which is the original finding.
//
//   2. REFRESH CONTROL — is there a reachable Refresh button, in the window
//      toolbar or the view hierarchy? This is what `refreshTriggers` adds, and
//      it is the only affordance a macOS user can actually reach.
//
// Expected after the refresh-triggers change: check 1 still NO (we did not
// switch containers), check 2 now YES.
//
// Run:  swift run SDKHarness

@main
struct SDKHarness: App {
    var body: some Scene {
        WindowGroup { Root() }
    }
}

private func sampleIssues() -> [SubmittedIssue] {
    (1...6).map { i in
        SubmittedIssue(
            id: UUID(),
            issueNumber: i,
            issueURL: URL(string: "https://github.com/awizemann/GitTickets/issues/\(i)")!,
            title: "Sample report \(i)",
            createdAt: Date(timeIntervalSince1970: 1_750_000_000 + Double(i * 3600)),
            replyCount: i
        )
    }
}

/// `swift run SDKHarness unmatched` reproduces the state a user sees when they
/// have filed reports but none come back — the dropped-label case AND the
/// all-deleted case, which are indistinguishable. Stays open so the copy can be
/// read; the wording here has been wrong before, and it is only checkable by
/// eye (there is no snapshot coverage of this view).
private let unmatchedMode = CommandLine.arguments.contains("unmatched")

struct Root: View {
    var body: some View {
        Group {
            if unmatchedMode {
                GitTicketsMyIssuesView(
                    loadDetailed: { MyIssuesRefresh(issues: [], requestedCount: 3) },
                    detail: { IssueDetailView(issue: $0) }
                )
            } else {
                GitTicketsMyIssuesView(
                    loadIssues: { sampleIssues() },
                    detail: { IssueDetailView(issue: $0) }
                )
            }
        }
        .frame(width: 560, height: 460)
        .task {
            guard !unmatchedMode else {
                print("unmatched mode: window stays open — read the copy, then quit.")
                return
            }
            try? await Task.sleep(for: .seconds(3))
            report()
            exit(0)
        }
    }
}

@MainActor
func report() {
    guard let window = NSApplication.shared.windows.first(where: { $0.isVisible })
            ?? NSApplication.shared.windows.first,
          let root = window.contentView else {
        print("DUMP: no window")
        return
    }

    // --- check 1: scroll-view refresh proxy ---
    var scrollViews: [NSScrollView] = []
    collectScrollViews(root, into: &scrollViews)
    print("scrollViewCount=\(scrollViews.count)")
    var anyProxy = false
    for sv in scrollViews {
        let subs = sv.subviews.map { String(describing: type(of: $0)) }
        let hasProxy = subs.contains { $0.contains("Refresh") }
        anyProxy = anyProxy || hasProxy
        print("SCROLLVIEW class=\(type(of: sv)) hasRefreshProxy=\(hasProxy)")
        print("   subviews=[\(subs.joined(separator: ", "))]")
    }
    print("CHECK1 scrollViewRefreshProxy=\(anyProxy)")

    // --- check 2: a reachable Refresh control ---
    var controls: [String] = []
    if let toolbar = window.toolbar {
        for item in toolbar.items {
            let label = item.label
            let axLabel = item.view?.accessibilityLabel() ?? ""
            controls.append("toolbarItem(id=\(item.itemIdentifier.rawValue), label=\"\(label)\", ax=\"\(axLabel)\")")
            // The button itself usually lives inside the item's own view, which
            // is NOT part of contentView's tree.
            if let itemView = item.view {
                collectRefreshControls(itemView, into: &controls)
            }
        }
    }
    // Walk the whole window frame, not just contentView — a macOS toolbar is
    // rendered in the titlebar, which is a sibling of contentView.
    let frameView = root.superview ?? root
    collectRefreshControls(frameView, into: &controls)

    let refreshControls = controls.filter { $0.lowercased().contains("refresh") }
    for c in controls { print("CONTROL \(c)") }
    print("CHECK2 refreshControlFound=\(!refreshControls.isEmpty) matches=\(refreshControls.count)")

    print("VERDICT userReachableRefreshOnMacOS=\(anyProxy || !refreshControls.isEmpty)")
}

@MainActor
private func collectScrollViews(_ view: NSView, into out: inout [NSScrollView]) {
    if let sv = view as? NSScrollView { out.append(sv) }
    for sub in view.subviews { collectScrollViews(sub, into: &out) }
}

/// SwiftUI hosts toolbar buttons inside its own views, so an `NSButton`-only
/// scan misses them. Report ANY view carrying an accessibility label, title, or
/// tooltip — that is where "Refresh reports" will surface.
@MainActor
private func collectRefreshControls(_ view: NSView, into out: inout [String]) {
    let ax = view.accessibilityLabel() ?? ""
    let axTitle = view.accessibilityTitle() ?? ""
    let help = view.toolTip ?? ""
    let buttonTitle = (view as? NSButton)?.title ?? ""
    if !ax.isEmpty || !axTitle.isEmpty || !help.isEmpty || !buttonTitle.isEmpty {
        out.append(
            "view(class=\(type(of: view)), ax=\"\(ax)\", axTitle=\"\(axTitle)\", help=\"\(help)\", title=\"\(buttonTitle)\")"
        )
    }
    for sub in view.subviews { collectRefreshControls(sub, into: &out) }
}
