import XCTest
@testable import GitTickets

final class DiagnosticsCollectorTests: XCTestCase {

    func test_defaultPolicyProducesNonEmptyBlob() {
        let blob = DiagnosticsCollector.collect(policy: .default)
        XCTAssertFalse(blob.text.isEmpty)
        XCTAssertFalse(blob.sections.isEmpty)
    }

    func test_defaultPolicyIncludesExpectedHeaders() {
        let blob = DiagnosticsCollector.collect(policy: .default)
        XCTAssertTrue(blob.text.contains("OS:"))
        XCTAssertTrue(blob.text.contains("App:"))
        XCTAssertTrue(blob.text.contains("Device:"))
        XCTAssertTrue(blob.text.contains("Locale:"))
        XCTAssertTrue(blob.text.contains("Free disk:"))
        XCTAssertTrue(blob.text.contains("Memory (physical):"))
    }

    func test_disablingFieldsProducesNarrowBlob() {
        let policy = DiagnosticsPolicy(
            includeOSVersion: true,
            includeAppVersion: false,
            includeDeviceModel: false,
            includeLocale: false,
            includeMemoryPressure: false,
            includeFreeDisk: false
        )
        let blob = DiagnosticsCollector.collect(policy: policy)
        XCTAssertTrue(blob.text.contains("OS:"))
        XCTAssertFalse(blob.text.contains("App:"))
        XCTAssertFalse(blob.text.contains("Device:"))
    }

    func test_emptyPolicyProducesEmptyBlob() {
        let policy = DiagnosticsPolicy(
            includeOSVersion: false,
            includeAppVersion: false,
            includeDeviceModel: false,
            includeLocale: false,
            includeMemoryPressure: false,
            includeFreeDisk: false,
            osLogSubsystems: []
        )
        let blob = DiagnosticsCollector.collect(policy: policy)
        XCTAssertEqual(blob.text, "")
        XCTAssertTrue(blob.sections.isEmpty)
    }

    func test_redactionRunsOnAssembledBlob() {
        // Force a synthetic redactor that finds "OS:" and replaces it.
        let pattern = try! NSRegularExpression(pattern: "OS:", options: [])
        let policy = DiagnosticsPolicy(
            redactors: [
                DiagnosticsRedactor(name: "test", regex: pattern, replacement: "REDACTED-HEADER")
            ]
        )
        let blob = DiagnosticsCollector.collect(policy: policy)
        XCTAssertFalse(blob.text.contains("OS:"))
        XCTAssertTrue(blob.text.contains("REDACTED-HEADER"))
    }
}
