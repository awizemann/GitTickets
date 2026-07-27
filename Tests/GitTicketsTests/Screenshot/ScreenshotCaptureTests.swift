import XCTest
@testable import GitTickets

final class ScreenshotCaptureTests: XCTestCase {

    // MARK: Failure copy shown in the form

    /// Every failure must offer the way forward. A capture that fails costs the
    /// user nothing — "Add image" is right there and submission is unaffected —
    /// so a message that only reports the failure would leave them stuck for no
    /// reason.
    func test_everyFailureMessageOffersTheAlternative() {
        let errors: [ScreenshotCaptureError] = [
            .permissionRequired,
            .noActiveWindow,
            .encodingFailed,
            .captureFailed("boom"),
        ]
        for error in errors {
            let message = ScreenshotCapture.failureMessage(for: error)
            XCTAssertTrue(
                message.contains("add an image") || message.contains("Add image"),
                "no alternative offered for \(error): \(message)"
            )
            XCTAssertFalse(message.isEmpty)
        }
    }

    /// Permission is a shrug, not an incident. The SDK deliberately does not
    /// nag for Screen Recording, so the copy must not send the user to System
    /// Settings or imply they did something wrong.
    func test_permissionMessageDoesNotNag() {
        let message = ScreenshotCapture.failureMessage(for: .permissionRequired)
        for nag in ["System Settings", "System Preferences", "Privacy & Security", "grant", "enable"] {
            XCTAssertFalse(
                message.contains(nag),
                "permission copy should not push the user to fix it — found \"\(nag)\""
            )
        }
    }

    /// The raw underlying error string is diagnostic detail, not user-facing.
    func test_captureFailedMessageDoesNotLeakTheUnderlyingError() {
        let message = ScreenshotCapture.failureMessage(for: .captureFailed("SCStreamErrorDomain -3801"))
        XCTAssertFalse(message.contains("SCStreamErrorDomain"))
        XCTAssertFalse(message.contains("-3801"))
    }

    /// ...but the adopter DOES need it, so the diagnostic variant keeps it.
    /// Hiding the cause from the user must not mean hiding it from the
    /// developer, or a missing permission becomes unexplainable in the field.
    func test_diagnosticMessageKeepsWhatTheUserMessageDrops() {
        XCTAssertTrue(
            ScreenshotCapture.diagnosticMessage(for: .captureFailed("SCStreamErrorDomain -3801"))
                .contains("SCStreamErrorDomain -3801")
        )
        let permission = ScreenshotCapture.diagnosticMessage(for: .permissionRequired)
        XCTAssertTrue(permission.contains("Screen Recording"))
        XCTAssertTrue(
            permission.contains("submission is unaffected"),
            "the adopter should be told this is non-fatal, not just what broke"
        )
    }

    // MARK: Error type

    func test_errorEqualityWorks() {
        XCTAssertEqual(ScreenshotCaptureError.permissionRequired, .permissionRequired)
        XCTAssertEqual(ScreenshotCaptureError.encodingFailed, .encodingFailed)
        XCTAssertEqual(ScreenshotCaptureError.noActiveWindow, .noActiveWindow)
        XCTAssertEqual(
            ScreenshotCaptureError.captureFailed("x"),
            .captureFailed("x")
        )
        XCTAssertNotEqual(
            ScreenshotCaptureError.captureFailed("x"),
            .captureFailed("y")
        )
    }

    func test_errorNoTwoCasesEqualAcrossKind() {
        XCTAssertNotEqual(
            ScreenshotCaptureError.permissionRequired,
            ScreenshotCaptureError.encodingFailed
        )
        XCTAssertNotEqual(
            ScreenshotCaptureError.captureFailed("oops"),
            ScreenshotCaptureError.encodingFailed
        )
    }
}
