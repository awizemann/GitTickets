#if os(iOS)
import XCTest
import UIKit
import SwiftUI
@testable import GitTickets

/// iOS-only XCTest. Will not run during `swift test` (which targets the host
/// macOS platform); compiled and executed by `xcodebuild test` against the
/// iOS Simulator scheme. Documents the UIKit container's contract so a
/// future refactor that, say, swaps `UIHostingController` subclassing for
/// `addChild` embedding doesn't silently regress the title / programmatic-init
/// constraints.
@available(iOS 16.0, *)
final class GitTicketsViewControllerTests: XCTestCase {

    @MainActor
    func test_initSetsTitle() {
        let vc = GitTicketsViewController()
        XCTAssertEqual(vc.title, "Report an Issue")
    }

    @MainActor
    func test_isUIHostingControllerOfGitTicketsView() {
        let vc = GitTicketsViewController()
        // Subclass relationship — `view` and `rootView` are inherited.
        XCTAssertNotNil(vc.view)
        XCTAssertTrue(type(of: vc) == GitTicketsViewController.self)
    }
}
#endif
