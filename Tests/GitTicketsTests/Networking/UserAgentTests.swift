import XCTest
@testable import GitTickets

final class UserAgentTests: XCTestCase {

    func test_userAgentContainsRequiredParts() {
        let ua = UserAgent.string()
        XCTAssertTrue(ua.hasPrefix("GitTickets/"))
        XCTAssertTrue(ua.contains("("))
        XCTAssertTrue(ua.contains(")"))
        XCTAssertTrue(ua.contains(UserAgent.sdkVersion))
    }

    func test_userAgentMentionsPlatform() {
        let ua = UserAgent.string()
        #if os(macOS)
        XCTAssertTrue(ua.contains("macOS"))
        #elseif os(iOS)
        XCTAssertTrue(ua.contains("iOS"))
        #endif
    }
}
