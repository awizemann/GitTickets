#if os(macOS)
import Foundation
import AppKit
import CoreGraphics
@preconcurrency import ScreenCaptureKit

extension ScreenshotCapture {

    /// macOS capture using ScreenCaptureKit's one-shot `SCScreenshotManager`
    /// (macOS 14+, which is the package floor).
    static func platformCapture() async -> Result<Data, ScreenshotCaptureError> {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            guard let display = content.displays.first else {
                return .failure(.captureFailed("No displays available"))
            }
            let filter = SCContentFilter(display: display, excludingWindows: [])
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

    private static func pngData(from cgImage: CGImage) -> Data? {
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return bitmap.representation(using: .png, properties: [:])
    }
}
#endif
