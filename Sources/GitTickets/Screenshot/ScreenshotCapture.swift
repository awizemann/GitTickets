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
    /// macOS: uses ScreenCaptureKit's `SCScreenshotManager` to capture the
    /// main display.
    ///
    /// iOS: renders the active window into a `UIGraphicsImageRenderer`.
    ///
    /// Captures **everything currently on screen**. Call it *before* you put
    /// your own reporting UI up, or that UI lands in the shot — see
    /// ``captureExcludingReporter()`` for the in-form case.
    public static func capture() async -> Result<Data, ScreenshotCaptureError> {
        await platformCapture(excludingReporter: false)
    }

    /// Captures the screen with GitTickets' own report UI left out.
    ///
    /// The built-in form's "Add screenshot" button uses this. Without it the
    /// button would be worse than useless: the user taps it to show you a
    /// problem and gets a picture of the form covering that problem.
    ///
    /// - macOS: the report window is excluded from the ScreenCaptureKit content
    ///   filter, so the shot is the app underneath with no gap or flicker. The
    ///   window is identified as the key window at capture time, which is sound
    ///   because the user just clicked a button in it.
    /// - iOS: renders the root view controller's view rather than the whole
    ///   window. A modally-presented form lives in a sibling transition view, so
    ///   rendering the root excludes it and its dimming.
    ///
    /// Edge case, on both platforms: if the host embeds the form as its root UI
    /// rather than presenting it over something, there is nothing underneath to
    /// exclude and the result is the same as ``capture()``.
    static func captureExcludingReporter() async -> Result<Data, ScreenshotCaptureError> {
        await platformCapture(excludingReporter: true)
    }

    /// One line to show in the form when capture fails.
    ///
    /// Every case is **non-blocking** — the user can always still submit, and
    /// can always attach an image by hand instead. Permission in particular is
    /// a shrug, not an error: the SDK does not nag for Screen Recording, so the
    /// message points at the alternative rather than at System Settings.
    ///
    /// Pure and separate from the view so the wording is testable; the
    /// screenshot copy on the neighbouring screen has already been wrong once.
    static func failureMessage(for error: ScreenshotCaptureError) -> String {
        switch error {
        case .permissionRequired:
            // Deliberately does not mention Screen Recording, System Settings,
            // or permission at all. The user came here to report a bug, not to
            // be handed a second chore; the real reason goes to the logger.
            "Screenshots aren't available on this device. You can add an image instead."
        case .noActiveWindow:
            "There's nothing to capture right now. You can add an image instead."
        case .encodingFailed:
            "That screenshot couldn't be saved. You can add an image instead."
        case .captureFailed:
            "Couldn't take a screenshot just now. You can add an image instead."
        }
    }

    /// Developer-facing detail for a failed capture, for ``Configuration/logger``.
    ///
    /// Split from ``failureMessage(for:)`` on purpose: the adopter needs to know
    /// it was a missing Screen Recording grant, and the user does not.
    static func diagnosticMessage(for error: ScreenshotCaptureError) -> String {
        switch error {
        case .permissionRequired:
            "Screenshot capture was refused: Screen Recording permission is not granted for this app (macOS). The form fell back to manual image attachment; submission is unaffected."
        case .noActiveWindow:
            "Screenshot capture found no active window to render."
        case .encodingFailed:
            "Screenshot captured but PNG encoding failed."
        case .captureFailed(let detail):
            "Screenshot capture failed: \(detail)"
        }
    }
}
