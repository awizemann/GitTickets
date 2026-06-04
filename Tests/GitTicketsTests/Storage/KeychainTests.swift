import XCTest
@testable import GitTickets

final class KeychainTests: XCTestCase {

    private var service: String!
    private let account = "test-account"

    override func setUp() {
        super.setUp()
        service = "com.gittickets.tests.\(UUID().uuidString)"
    }

    override func tearDown() {
        try? Keychain.delete(service: service, account: account)
        super.tearDown()
    }

    func test_readMissingReturnsNil() throws {
        XCTAssertNil(try Keychain.read(service: service, account: account))
    }

    func test_writeThenRead() throws {
        let payload = Data("hello".utf8)
        try Keychain.write(service: service, account: account, data: payload)
        XCTAssertEqual(try Keychain.read(service: service, account: account), payload)
    }

    func test_writeIsIdempotent() throws {
        try Keychain.write(service: service, account: account, data: Data("v1".utf8))
        try Keychain.write(service: service, account: account, data: Data("v2".utf8))
        XCTAssertEqual(try Keychain.read(service: service, account: account), Data("v2".utf8))
    }

    func test_deleteRemoves() throws {
        try Keychain.write(service: service, account: account, data: Data("x".utf8))
        try Keychain.delete(service: service, account: account)
        XCTAssertNil(try Keychain.read(service: service, account: account))
    }

    func test_deleteMissingIsNoOp() {
        XCTAssertNoThrow(try Keychain.delete(service: service, account: account))
    }
}
