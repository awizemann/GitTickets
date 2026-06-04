import XCTest
@testable import GitTickets

final class DeviceIdentityTests: XCTestCase {

    private var identity: DeviceIdentity!

    override func setUp() {
        super.setUp()
        let service = "com.gittickets.tests.deviceid.\(UUID().uuidString)"
        identity = DeviceIdentity(service: service, account: "device")
    }

    override func tearDown() {
        try? identity.reset()
        super.tearDown()
    }

    func test_currentReturnsNilWhenAbsent() throws {
        XCTAssertNil(try identity.current())
    }

    func test_currentOrGenerateProducesStableValue() throws {
        let first = try identity.currentOrGenerate()
        let second = try identity.currentOrGenerate()
        XCTAssertEqual(first, second)
        XCTAssertNotNil(UUID(uuidString: first))
    }

    func test_resetClearsValue() throws {
        let first = try identity.currentOrGenerate()
        try identity.reset()
        XCTAssertNil(try identity.current())
        let second = try identity.currentOrGenerate()
        XCTAssertNotEqual(first, second)
    }
}
