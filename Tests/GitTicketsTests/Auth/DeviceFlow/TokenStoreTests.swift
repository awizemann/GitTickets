import XCTest
@testable import GitTickets

final class TokenStoreTests: XCTestCase {

    private var service: String!

    override func setUp() {
        super.setUp()
        service = "com.gittickets.tests.token-store.\(UUID().uuidString)"
    }

    override func tearDown() {
        try? Keychain.delete(service: service, account: TokenStore.defaultAccount)
        super.tearDown()
    }

    func test_readMissingReturnsNil() throws {
        let store = TokenStore(service: service)
        XCTAssertNil(try store.read())
    }

    func test_writeThenRead() throws {
        let store = TokenStore(service: service)
        try store.write("gho_secret_token")
        XCTAssertEqual(try store.read(), "gho_secret_token")
    }

    func test_writeOverwrites() throws {
        let store = TokenStore(service: service)
        try store.write("token-v1")
        try store.write("token-v2")
        XCTAssertEqual(try store.read(), "token-v2")
    }

    func test_deleteRemovesToken() throws {
        let store = TokenStore(service: service)
        try store.write("gho_x")
        try store.delete()
        XCTAssertNil(try store.read())
    }

    func test_deleteMissingIsNoOp() throws {
        let store = TokenStore(service: service)
        XCTAssertNoThrow(try store.delete())
    }

    /// Footgun guard: two TokenStores constructed for distinct host bundles must not
    /// share a Keychain item. Without bundle-id namespacing, two same-team apps would
    /// read each other's OAuth tokens.
    func test_distinctHostBundlesGetDistinctTokens() throws {
        let storeA = TokenStore(hostBundleIdentifier: "com.example.a-\(UUID())")
        let storeB = TokenStore(hostBundleIdentifier: "com.example.b-\(UUID())")
        defer {
            try? storeA.delete()
            try? storeB.delete()
        }
        try storeA.write("token-a")
        try storeB.write("token-b")
        XCTAssertEqual(try storeA.read(), "token-a")
        XCTAssertEqual(try storeB.read(), "token-b")
    }
}
