#if os(macOS)
import Foundation
import AppKit
import CoreGraphics
@preconcurrency import ScreenCaptureKit

extension ScreenshotCapture {

    /// macOS capture using ScreenCaptureKit's one-shot `SCScreenshotManager`
    /// (macOS 14+, which is the package floor).
    static func platformCapture(excludingReporter: Bool) async -> Result<Data, ScreenshotCaptureError> {
        do {
            // Read the reporter window BEFORE any await. `NSApp.keyWindow` is
            // live state: if focus moves while `SCShareableContent` is in
            // flight, a later read names a different window, and we would
            // exclude the wrong one — capturing the form and hiding exactly
            // what the user meant to show. Reported by an adopter.
            let reporterID = excludingReporter ? await reporterWindowID() : nil

            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            guard let display = content.displays.first else {
                return .failure(.captureFailed("No displays available"))
            }

            let filter: SCContentFilter
            if excludingReporter {
                // Scope to THIS application's windows only, minus the report
                // window. `excludingWindows:` alone would capture the whole
                // display — every other app, the desktop, everything — and
                // that content can end up attached to a public issue. The form
                // promises a picture of the app behind it, so that is all it
                // may take.
                let ownApplications = content.applications.filter {
                    $0.processID == ProcessInfo.processInfo.processIdentifier
                }
                let excluded = reporterID.map { id in
                    content.windows.filter { $0.windowID == id }
                } ?? []
                filter = SCContentFilter(
                    display: display,
                    including: ownApplications,
                    exceptingWindows: excluded
                )
            } else {
                // Public `capture()` — documented as everything on screen, for
                // hosts capturing before they present their own UI. Unchanged.
                filter = SCContentFilter(display: display, excludingWindows: [])
            }
            let configuration = SCStreamConfiguration()
            configuration.width = Int(display.width)
            configuration.height = Int(display.height)
            configuration.capturesAudio = false
            configuration.showsCursor = false

            let cgImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )

            guard let data = pngData(from: cgImage) else {
                return .failure(.encodingFailed)
            }
            return .success(data)
        } catch {
            // ScreenCaptureKit returns an error containing "user has not granted"
            // wording when Screen Recording permission is missing.
            let description = String(describing: error).lowercased()
            if description.contains("permission") || description.contains("not granted") || description.contains("tccd") {
                return .failure(.permissionRequired)
            }
            return .failure(.captureFailed(String(describing: error)))
        }
    }

    /// `CGWindowID` of the window the capture was started from, if any.
    ///
    /// `NSWindow.windowNumber` and `SCWindow.windowID` are the same coordinate
    /// space, so this maps cleanly onto the ScreenCaptureKit content list.
    @MainActor
    private static func reporterWindowID() -> CGWindowID? {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return nil }
        let number = window.windowNumber
        guard number > 0 else { return nil }
        return CGWindowID(number)
    }

    private static func pngData(from cgImage: CGImage) -> Data? {
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return bitmap.representation(using: .png, properties: [:])
    }
}
#endif
