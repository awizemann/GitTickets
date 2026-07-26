import SwiftUI
import AppKit

// macOS counterpart. AppKit has no UIRefreshControl equivalent, so "look for
// the refresh control class" is not available as a test. Instead this diffs the
// view hierarchy: the SAME ScrollView is rendered with and without
// `.refreshable`. If the modifier installs any pull affordance, the two
// hierarchies must differ. If they are identical, there is nothing to pull.
//
// It also reports whether the `refresh` environment action is installed inside
// each container — a host could invoke that programmatically even with no
// gesture, so the two questions are genuinely separate.
//
// Prints to stdout and exits; no screenshot or input injection needed.

@main
struct MacHarness: App {
    var body: some Scene {
        WindowGroup { Root() }
    }
}

struct RefreshProbe: View {
    let label: String
    @Environment(\.refresh) private var refresh
    var body: some View {
        Text("\(label) env.refresh: \(refresh == nil ? "nil" : "PRESENT")")
            .font(.system(size: 10))
            .onAppear {
                print("ENV \(label): \(refresh == nil ? "nil" : "PRESENT")")
            }
    }
}

struct Root: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack {
                Text("A: ScrollView, NO refreshable").font(.caption)
                ScrollView {
                    VStack {
                        RefreshProbe(label: "A-plain-scrollview")
                        ForEach(0..<15, id: \.self) { Text("row \($0)") }
                    }
                }
                .frame(width: 210, height: 220)
                .border(.gray)
            }
            VStack {
                Text("B: ScrollView, refreshable").font(.caption)
                ScrollView {
                    VStack {
                        RefreshProbe(label: "B-refreshable-scrollview")
                        ForEach(0..<15, id: \.self) { Text("row \($0)") }
                    }
                }
                .frame(width: 210, height: 220)
                .border(.blue)
                .refreshable { }
            }
            VStack {
                Text("C: List, refreshable").font(.caption)
                List {
                    RefreshProbe(label: "C-refreshable-list")
                    ForEach(0..<15, id: \.self) { Text("row \($0)") }
                }
                .frame(width: 210, height: 220)
                .border(.green)
                .refreshable { }
            }
        }
        .padding(10)
        .task {
            try? await Task.sleep(for: .seconds(2))
            dumpHierarchy()
            exit(0)
        }
    }
}

@MainActor
func dumpHierarchy() {
    guard let window = NSApplication.shared.windows.first(where: { $0.isVisible }) ?? NSApplication.shared.windows.first,
          let root = window.contentView else {
        print("DUMP: no window")
        return
    }
    var scrollViews: [(NSScrollView, CGFloat)] = []
    collect(root, into: &scrollViews, window: window)
    // Left-to-right so A, B, C come out in order.
    for (sv, x) in scrollViews.sorted(by: { $0.1 < $1.1 }) {
        print("SCROLLVIEW x=\(Int(x)) class=\(type(of: sv))")
        print("   documentView=\(sv.documentView.map { String(describing: type(of: $0)) } ?? "nil")")
        print("   directSubviews=[\(sv.subviews.map { String(describing: type(of: $0)) }.joined(separator: ", "))]")
        print("   floatingSubviews=\(sv.subviews.filter { sv.documentView !== $0 }.count)")
    }
}

@MainActor
private func collect(_ view: NSView, into out: inout [(NSScrollView, CGFloat)], window: NSWindow) {
    if let sv = view as? NSScrollView {
        let x = sv.convert(sv.bounds, to: nil).origin.x
        out.append((sv, x))
    }
    for sub in view.subviews { collect(sub, into: &out, window: window) }
}
