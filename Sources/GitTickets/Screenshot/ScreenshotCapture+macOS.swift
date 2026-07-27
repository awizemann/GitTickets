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
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            guard let display = content.displays.first else {
                return .failure(.captureFailed("No displays available"))
            }
            // Leave the report window out when the capture was started from
            // inside it, or the user gets a picture of the form covering the
            // thing they are trying to show us. Key window is the right handle:
            // they just clicked a button in it.
            var excluded: [SCWindow] = []
            if excludingReporter, let reporterID = await reporterWindowID() {
                excluded = content.windows.filter { $0.windowID == reporterID }
            }
            let filter = SCContentFilter(display: display, excludingWindows: excluded)
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
