#if os(macOS)
import AppKit

/// AppKit factory for the "Report an Issue\u{2026}" menu item. Hosts that
/// drive their menu bar with AppKit (no SwiftUI `Commands` group) call this
/// to get a fully-wired `NSMenuItem` ready for insertion:
///
/// ```swift
/// let item = GitTicketsMenuItemFactory.makeReportIssueItem()
/// NSApp.helpMenu?.addItem(item)
/// ```
///
/// The default action calls `ReportWindowController.shared.showWindow(nil)`.
/// Pass a custom `action` to hook the menu entry into a different presenter
/// (e.g. an existing modal sheet or a host-owned window controller).
@available(macOS 13.0, *)
public enum GitTicketsMenuItemFactory {

    /// Builds an `NSMenuItem` wired to the given action.
    ///
    /// - Parameters:
    ///   - title: Menu entry text.
    ///   - systemImage: SF Symbol drawn at leading edge of the menu item.
    ///     Defaults to `"exclamationmark.bubble"`, matching the SwiftUI
    ///     ``GitTicketsCommands`` default and the form's header icon. Pass
    ///     `nil` for a text-only entry.
    ///   - keyEquivalent: Cocoa key-equivalent string. Empty (default) means no shortcut.
    ///   - keyEquivalentModifierMask: Modifier mask for the key equivalent.
    ///   - action: Invoked when the user picks the menu item. Defaults to
    ///     opening the shared ``ReportWindowController``.
    /// - Returns: An `NSMenuItem` ready for insertion into any `NSMenu`.
    public static func makeReportIssueItem(
        title: String = "Report an Issue\u{2026}",
        systemImage: String? = "exclamationmark.bubble",
        keyEquivalent: String = "",
        keyEquivalentModifierMask: NSEvent.ModifierFlags = [],
        action: @escaping () -> Void = { ReportWindowController.shared.showWindow(nil) }
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: #selector(MenuActionTarget.fire(_:)),
            keyEquivalent: keyEquivalent
        )
        item.keyEquivalentModifierMask = keyEquivalentModifierMask
        if let systemImage {
            item.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)
        }
        let target = MenuActionTarget(action: action)
        item.target = target
        // NSMenuItem.target is a weak reference. If we let `target` go out of
        // scope here, the action would never fire. Stash it in
        // representedObject (which is strong) so the lifetime is tied to the
        // menu item itself.
        item.representedObject = target
        return item
    }
}

/// Thin trampoline that bridges the menu item's `@objc` selector call to a
/// Swift closure. Lives long enough because the owning `NSMenuItem` retains
/// it via `representedObject`.
@available(macOS 13.0, *)
final class MenuActionTarget: NSObject {
    let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    @objc func fire(_ sender: Any?) {
        action()
    }
}
#endif
