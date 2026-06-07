// Examples/AppKitSampleApp/AppKitSampleApp.swift
//
// A complete reference for integrating GitTickets into a pure AppKit macOS
// app — no SwiftUI App scene. Uses `GitTicketsMenuItemFactory` to drop a
// menu entry into the Help menu and `ReportWindowController.shared` to
// host the form in a standalone window.
//
// Drop this file into a new "App" project with no Storyboards (delete
// `MainMenu.xib`, `Info.plist` keep `Principal class = NSApplication`,
// add a `main.swift` with `NSApplicationMain` substitute — see Apple's
// docs for "Build an AppKit app without a storyboard"). Then add the
// GitTickets package as a dependency and replace placeholders below.

import AppKit
import GitTickets

@main
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureGitTickets()
        installMenuBar()
        showWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: - GitTickets

    private func configureGitTickets() {
        guard
            let relayURL = URL(string: "https://your-relay.vercel.app"),
            let secret = SharedSecret(hex: "<your-shared-secret-hex>")
        else {
            preconditionFailure("Replace the relay URL + secret placeholders before running.")
        }

        GitTickets.configure(.init(
            repo: RepoCoordinate(
                owner: "<your-github-org-or-user>",
                name: "<your-repo>",
                visibility: .public
            ),
            auth: .relay(url: relayURL, sharedSecret: secret)
        ))
    }

    // MARK: - Menu bar

    /// Builds a minimal menu bar with an Application menu (Quit) and a Help
    /// menu containing the "Report an Issue\u{2026}" item produced by the
    /// package factory.
    private func installMenuBar() {
        let mainMenu = NSMenu()

        // App menu (the leftmost one)
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(
            title: "Quit AppKitSampleApp",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Help menu — drop in the GitTickets report item.
        let helpMenuItem = NSMenuItem()
        let helpMenu = NSMenu(title: "Help")
        helpMenu.addItem(GitTicketsMenuItemFactory.makeReportIssueItem())
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)

        NSApp.mainMenu = mainMenu
        NSApp.helpMenu = helpMenu
    }

    // MARK: - Main window

    /// Shows a small placeholder window. The actual report UX opens from the
    /// menu item; this window is just here so the app has *something* visible
    /// at launch.
    private func showWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "AppKitSampleApp"
        window.center()

        let label = NSTextField(labelWithString: "Open Help ▸ Report an Issue\u{2026} to file a bug.")
        label.font = NSFont.systemFont(ofSize: 14)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        window.contentView = container
        window.makeKeyAndOrderFront(nil)
    }
}
