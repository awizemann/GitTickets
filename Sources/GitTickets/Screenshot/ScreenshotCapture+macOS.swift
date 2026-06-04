#if os(macOS)
import Foundation
import AppKit
import CoreGraphics
@preconcurrency import ScreenCaptureKit

extension ScreenshotCapture {

    /// macOS capture using ScreenCaptureKit.
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

            let cgImage: CGImage
            if #available(macOS 14.0, *) {
                cgImage = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: configuration
                )
            } else {
                let stream = try await OneShotStream.capture(filter: filter, configuration: configuration)
                cgImage = stream
            }

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

/// Minimal one-shot frame grab for macOS 13 (no `SCScreenshotManager`).
@available(macOS 13.0, *)
private final class OneShotStream: NSObject, SCStreamOutput {
    private let continuation: CheckedContinuation<CGImage, Error>
    private let stream: SCStream

    private init(continuation: CheckedContinuation<CGImage, Error>, stream: SCStream) {
        self.continuation = continuation
        self.stream = stream
    }

    static func capture(filter: SCContentFilter, configuration: SCStreamConfiguration) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            do {
                let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
                let output = OneShotStream(continuation: continuation, stream: stream)
                try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: .main)
                Task {
                    do {
                        try await stream.startCapture()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        continuation.resume(returning: cgImage)
        Task { try? await stream.stopCapture() }
    }
}
#endif
