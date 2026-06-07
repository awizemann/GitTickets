import SwiftUI

/// SwiftUI `Commands` group that drops a "My Reports\u{2026}" entry into the
/// host app's Help menu (or whatever placement the host picks). The natural
/// sibling to ``GitTicketsCommands`` — present this one too if the app
/// surfaces the Phase 2 ``GitTicketsMyIssuesView``.
///
/// ```swift
/// .commands {
///     GitTicketsCommands { showingReport = true }
///     GitTicketsMyIssuesCommands { showingMyIssues = true }
/// }
/// ```
///
/// Both groups land in the same Cocoa placement when called with the same
/// `placement:` argument, so macOS renders them adjacent in the same menu
/// section.
@available(macOS 13.0, iOS 16.0, *)
public struct GitTicketsMyIssuesCommands: Commands {

    let title: String
    let systemImage: String?
    let placement: CommandGroupPlacement
    let isDisabled: Bool
    let keyboardShortcut: KeyboardShortcut?
    let action: () -> Void

    /// - Parameters:
    ///   - title: Menu entry text. Defaults to "My Reports\u{2026}".
    ///   - systemImage: SF Symbol shown next to the title in the menu. Defaults to
    ///     `"tray"` (matches the empty-state icon in ``GitTicketsMyIssuesView``).
    ///     Pass `nil` to render a text-only entry.
    ///   - placement: Where the entry lands. Defaults to ``CommandGroupPlacement/help``,
    ///     matching ``GitTicketsCommands``'s default. Pass ``CommandGroupPlacement/appInfo``
    ///     to put it in the application menu.
    ///   - isDisabled: Greys the entry out without removing it. Hosts use this to
    ///     reflect "SDK not yet configured" state.
    ///   - keyboardShortcut: Optional shortcut. Defaults to none.
    ///   - action: Invoked when the user selects the menu item.
    public init(
        title: String = "My Reports\u{2026}",
        systemImage: String? = "tray",
        placement: CommandGroupPlacement = .help,
        isDisabled: Bool = false,
        keyboardShortcut: KeyboardShortcut? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.placement = placement
        self.isDisabled = isDisabled
        self.keyboardShortcut = keyboardShortcut
        self.action = action
    }

    public var body: some Commands {
        CommandGroup(after: placement) {
            menuButton
        }
    }

    @ViewBuilder private var menuButton: some View {
        let button = Button(action: action) {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        if let keyboardShortcut {
            button
                .keyboardShortcut(keyboardShortcut)
                .disabled(isDisabled)
        } else {
            button.disabled(isDisabled)
        }
    }
}
