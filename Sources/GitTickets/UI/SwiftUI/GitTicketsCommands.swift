import SwiftUI

/// SwiftUI `Commands` group that drops a "Report an Issue\u{2026}" entry into
/// the host app's Help menu. The action closure is injected by the host so the
/// commands group stays UI-agnostic — present a sheet, open a window scene,
/// or call into ``ReportWindowController`` on macOS, whichever fits the app.
///
/// ```swift
/// @main
/// struct MyApp: App {
///     @State private var showingReport = false
///     var body: some Scene {
///         WindowGroup {
///             ContentView()
///                 .sheet(isPresented: $showingReport) { GitTicketsView() }
///         }
///         .commands {
///             GitTicketsCommands { showingReport = true }
///         }
///     }
/// }
/// ```
///
/// Placed via `CommandGroup(after: .help)` so it sits at the bottom of the
/// Help menu. Hosts that want it on a different menu can wrap the same
/// trigger in their own ``Commands`` group.
@available(macOS 13.0, iOS 16.0, *)
public struct GitTicketsCommands: Commands {

    let title: String
    let systemImage: String?
    let placement: CommandGroupPlacement
    let isDisabled: Bool
    let keyboardShortcut: KeyboardShortcut?
    let action: () -> Void

    /// - Parameters:
    ///   - title: Menu entry text. Defaults to "Report an Issue\u{2026}".
    ///   - systemImage: SF Symbol shown next to the title in the menu. Defaults to
    ///     `"exclamationmark.bubble"` (matches the form's header icon). Pass `nil`
    ///     to render a text-only entry.
    ///   - placement: Where the entry lands. Defaults to ``CommandGroupPlacement/help``
    ///     (bottom of the Help menu). Pass ``CommandGroupPlacement/appInfo`` for the
    ///     application menu (next to "About"), or any other Cocoa placement.
    ///   - isDisabled: Greys the entry out without removing it. Hosts use this to
    ///     reflect "SDK not yet configured" state — keeps the menu honest while a
    ///     developer is wiring up their relay credentials.
    ///   - keyboardShortcut: Optional shortcut. Defaults to none — Help-menu
    ///     items rarely need one and ⌘? is reserved by the system.
    ///   - action: Invoked when the user selects the menu item.
    public init(
        title: String = "Report an Issue\u{2026}",
        systemImage: String? = "exclamationmark.bubble",
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
