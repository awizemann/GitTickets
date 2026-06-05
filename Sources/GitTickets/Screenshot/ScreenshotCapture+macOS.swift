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
///
/// SCStream delivers sample buffers continuously until `stopCapture()` completes,
/// which is asynchronous. The output delegate may fire multiple times before the
/// stream actually stops — so we gate `continuation.resume(...)` behind a
/// lock-protected `didResume` flag. Resuming a CheckedContinuation twice
/// fatal-errors the process, which would crash any macOS 13 user the moment
/// they tapped "Add Screenshot".
@available(macOS 13.0, *)
private final class OneShotStream: NSObject, SCStreamOutput, @unchecked Sendable {
    private let continuation: CheckedContinuation<CGImage, Error>
    private let stream: SCStream
    private let lock = NSLock()
    private var didResume = false

    private init(continuation: CheckedContinuation<CGImage, Error>, stream: SCStream) {
        self.continuation = continuation
        self.stream = stream
    }

    static func capture(filter: SCContentFilter, configuration: SCStreamConfiguration) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
            let output = OneShotStream(continuation: continuation, stream: stream)
            do {
                try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: .main)
            } catch {
                output.finish(throwing: error, alreadyAdded: false)
                return
            }
            Task {
                do {
                    try await stream.startCapture()
                } catch {
                    // startCapture failed — the output is already registered
                    // and the stream is partially armed. Tear it down before
                    // resuming so we don't leak a stream that keeps the green
                    // capture indicator on.
                    output.finish(throwing: error, alreadyAdded: true)
                }
            }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        finish(returning: cgImage)
    }

    private func finish(returning image: CGImage) {
        lock.lock()
        if didResume {
            lock.unlock()
            return
        }
        didResume = true
        lock.unlock()
        continuation.resume(returning: image)
        Task { [stream] in
            try? stream.removeStreamOutput(self, type: .screen)
            try? await stream.stopCapture()
        }
    }

    private func finish(throwing error: Error, alreadyAdded: Bool) {
        lock.lock()
        if didResume {
            lock.unlock()
            return
        }
        didResume = true
        lock.unlock()
        continuation.resume(throwing: error)
        if alreadyAdded {
            Task { [stream] in
                try? stream.removeStreamOutput(self, type: .screen)
                try? await stream.stopCapture()
            }
        }
    }
}
#endif
