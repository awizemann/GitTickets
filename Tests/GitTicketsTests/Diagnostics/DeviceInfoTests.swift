import XCTest
@testable import GitTickets

final class DeviceInfoTests: XCTestCase {

    func test_machineIdentifierIsNonEmpty() {
        let id = DeviceInfo.machineIdentifier
        XCTAssertFalse(id.isEmpty)
        XCTAssertFalse(id.contains("\0"))
    }

    func test_knownIPhoneMapping() {
        XCTAssertEqual(DeviceInfo.humanReadable(for: "iPhone16,1"), "iPhone 15 Pro")
        XCTAssertEqual(DeviceInfo.humanReadable(for: "iPhone17,3"), "iPhone 16")
    }

    func test_knownMacMapping() {
        XCTAssertEqual(DeviceInfo.humanReadable(for: "Mac15,3"), "MacBook Pro (14-inch, M3)")
        XCTAssertEqual(DeviceInfo.humanReadable(for: "Mac16,1"), "MacBook Pro (14-inch, M4)")
    }

    func test_knownIPadMapping() {
        XCTAssertEqual(DeviceInfo.humanReadable(for: "iPad16,5"), "iPad Pro 13-inch (M4)")
    }

    func test_unknownIdentifierFallsBackToRaw() {
        XCTAssertEqual(DeviceInfo.humanReadable(for: "iPhone99,99"), "iPhone99,99")
    }

    func test_humanReadableForCurrentDeviceIsNonEmpty() {
        XCTAssertFalse(DeviceInfo.humanReadableModel.isEmpty)
    }
}
