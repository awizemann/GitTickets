import XCTest
@testable import GitTickets

final class ScreenshotCaptureTests: XCTestCase {

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
