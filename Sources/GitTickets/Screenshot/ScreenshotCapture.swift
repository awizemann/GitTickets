import Foundation

/// Reasons a screenshot capture can fail in a way the UI should surface
/// without blocking submission.
///
/// `permissionRequired` is the common one on macOS — Screen Recording in
/// System Settings → Privacy & Security. The form falls back to "submit
/// without screenshot" rather than treating it as a fatal error.
public enum ScreenshotCaptureError: Error, Equatable {
    /// User has not granted Screen Recording permission (macOS).
    case permissionRequired

    /// Underlying API returned an unexpected error.
    case captureFailed(String)

    /// No window was available to capture (iOS — key window not yet attached).
    case noActiveWindow

    /// PNG encoding of the captured image failed.
    case encodingFailed
}

/// Entry point for screenshot capture.
///
/// Capture is initiated only on direct user action (e.g. tapping
/// "Add Screenshot" in the form). The SDK never auto-captures in the
/// background — that would be surprising and creepy.
///
/// Returns PNG bytes ready to upload as an attachment. Errors are recoverable
/// — the caller (form view) surfaces the failure inline and allows submission
/// without a screenshot.
///
/// Public so hosts that present their own UI on top of
/// ``GitTickets/submit(_:)`` can capture a screenshot. Pass the returned
/// `Data` as ``Report/screenshot``.
///
/// > Note: On macOS this requires Screen Recording permission. Hosts that
/// > don't want to ask for that permission can use an `NSOpenPanel` for an
/// > image file instead — the result lands in the same ``Report/screenshot``
/// > / ``Report/attachments`` slots.
public enum ScreenshotCapture {

    /// Captures the current screen / key window.
    ///
    /// macOS: uses ScreenCaptureKit to capture the main display. Falls back
    /// to `CGWindowListCreateImage` if SCK is unavailable.
    ///
    /// iOS: renders the active window into a `UIGraphicsImageRenderer`.
    public static func capture() async -> Result<Data, ScreenshotCaptureError> {
        await platformCapture()
    }
}
