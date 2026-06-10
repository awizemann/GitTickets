import XCTest
@testable import GitTickets

final class DeviceIdentityTests: XCTestCase {

    private var identity: DeviceIdentity!

    override func setUpWithError() throws {
        try super.setUpWithError()
        #if targetEnvironment(simulator) && os(iOS)
        // iOS Sim XCTest bundles lack keychain-access-groups entitlement; every
        // SecItem* call returns errSecMissingEntitlement (-34018). Covered on
        // the macOS test job and on real devices. See:
        // .memory/footguns/footgun-ios-sim-xctest-has-no-keychain-entitlement.md
        throw XCTSkip("Keychain unavailable in iOS Simulator SPM test bundle")
        #else
        let service = "com.gittickets.tests.deviceid.\(UUID().uuidString)"
        identity = DeviceIdentity(service: service, account: "device")
        #endif
    }

    override func tearDown() {
        // `identity` is left nil on iOS Sim because setUpWithError throws
        // XCTSkip before assigning it.
        if let identity {
            try? identity.reset()
        }
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
