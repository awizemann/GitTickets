#if os(macOS)
import AppKit
import SwiftUI

/// AppKit `NSWindowController` that hosts ``GitTicketsView`` in a standalone
/// window. The natural pair to ``GitTicketsMenuItemFactory`` for hosts that
/// drive their menu bar with AppKit instead of a SwiftUI `Commands` group.
///
/// ```swift
/// let item = GitTicketsMenuItemFactory.makeReportIssueItem()
/// NSApp.helpMenu?.addItem(item)
/// ```
///
/// (`makeReportIssueItem` already wires the action to ``shared``.
/// `showWindow(_:)` on the shared controller brings the existing window
/// forward if it's already open, or builds a fresh one.)
///
/// Every call to ``showWindow(_:)`` replaces the window's content view
/// controller with a fresh ``GitTicketsView``, so the form starts blank each
/// time. Window position + size persist via `NSWindow.frameAutosaveName` so
/// returning users see the window where they left it.
@available(macOS 13.0, *)
public final class ReportWindowController: NSWindowController {

    /// Process-wide instance. Use this from menu actions so re-opening the
    /// menu while the window is already visible just brings it forward
    /// instead of stacking duplicates.
    public static let shared = ReportWindowController()

    public convenience init() {
        let window = Self.makeWindow()
        self.init(window: window)
        window.contentViewController = NSHostingController(rootView: GitTicketsView())
        windowFrameAutosaveName = "GitTickets.ReportWindow"
    }

    public override func showWindow(_ sender: Any?) {
        // Reset form state on every open — last session's typed-but-abandoned
        // body would otherwise leak into the next report. Replacing the
        // content view controller discards the SwiftUI view tree's @State.
        window?.contentViewController = NSHostingController(rootView: GitTicketsView())
        // Re-center if the autosaved frame is off-screen (external display
        // disconnected since last session, etc.).
        if let window, !window.isVisibleOnAnyScreen {
            window.center()
        }
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Report an Issue"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 480, height: 520)
        return window
    }
}

@available(macOS 13.0, *)
private extension NSWindow {
    /// Returns true if any screen contains at least a small portion of the
    /// window's saved frame. Used to decide whether to recenter on show — if
    /// the autosaved position is on a disconnected display, the user can't
    /// see the window at all.
    var isVisibleOnAnyScreen: Bool {
        let frame = self.frame
        for screen in NSScreen.screens where screen.visibleFrame.intersects(frame) {
            return true
        }
        return false
    }
}
#endif
