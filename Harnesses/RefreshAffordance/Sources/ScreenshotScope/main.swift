import SwiftUI
import AppKit
import GitTickets

// What does the form's screenshot button actually photograph?
//
// An adopter reported that the 2.4.0 docs promised "the app behind the form"
// while the code used SCContentFilter(display:excludingWindows:) — the whole
// display minus one window. That difference is other applications' content
// landing in a public issue, and no unit test can see it: the answer depends
// on ScreenCaptureKit and on what else happens to be on screen.
//
// So this puts a large, unmistakable marker window on screen, captures through
// the SAME code path the form uses, and writes both PNGs side by side:
//
//   own-app.png    <- captureExcludingReporter(), should contain ONLY this app
//   whole-screen.png <- public capture(), documented as everything
//
// Compare them. If own-app.png shows your other windows, wallpaper, or menu
// bar, the scoping is broken again.
//
// Run:  swift run ScreenshotScope
//
// macOS will refuse without Screen Recording permission for whatever binary is
// running this, which is itself a valid result — the form is supposed to
// degrade quietly in exactly that case.

@main
struct ScreenshotScopeHarness: App {
    var body: some Scene {
        WindowGroup { Marker() }
    }
}

struct Marker: View {
    @State private var status = "capturing…"

    var body: some View {
        VStack(spacing: 14) {
            Text("GITTICKETS CAPTURE SCOPE MARKER")
                .font(.system(size: 26, weight: .black, design: .monospaced))
                .foregroundStyle(.white)
            Text("This window belongs to the harness process.\nIt MUST appear in own-app.png.")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
            Text(status)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.yellow)
                .textSelection(.enabled)
        }
        .frame(width: 620, height: 260)
        .background(Color.purple)
        .task {
            // Let the window actually appear before photographing it.
            try? await Task.sleep(for: .seconds(2))
            status = await run()
            try? await Task.sleep(for: .seconds(1))
            exit(0)
        }
    }
}

@MainActor
func run() async -> String {
    let outDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build-scope")
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    var lines: [String] = []

    // Same entry point the form's button uses.
    switch await ScreenshotCapture.captureExcludingReporter() {
    case .success(let data):
        let url = outDir.appendingPathComponent("own-app.png")
        try? data.write(to: url)
        lines.append("own-app.png \(data.count) bytes -> \(url.path)")
    case .failure(let error):
        lines.append("own-app FAILED: \(ScreenshotCapture.diagnosticMessage(for: error))")
    }

    switch await ScreenshotCapture.capture() {
    case .success(let data):
        let url = outDir.appendingPathComponent("whole-screen.png")
        try? data.write(to: url)
        lines.append("whole-screen.png \(data.count) bytes -> \(url.path)")
    case .failure(let error):
        lines.append("whole-screen FAILED: \(ScreenshotCapture.diagnosticMessage(for: error))")
    }

    for line in lines { print("SCOPE \(line)") }
    return lines.joined(separator: "\n")
}
