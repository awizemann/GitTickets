import XCTest
@testable import GitTickets

final class BodyTemplatesTests: XCTestCase {

    func test_bugTemplateContainsExpectedHeaders() {
        let body = BodyTemplates.starter(for: .bug)
        XCTAssertTrue(body.contains("### What happened?"))
        XCTAssertTrue(body.contains("### Steps to reproduce"))
    }

    func test_featureRequestTemplateContainsExpectedHeaders() {
        let body = BodyTemplates.starter(for: .featureRequest)
        XCTAssertTrue(body.contains("### Problem to solve"))
        XCTAssertTrue(body.contains("### Proposed solution"))
    }

    func test_questionTemplateIsMinimal() {
        let body = BodyTemplates.starter(for: .question)
        XCTAssertTrue(body.contains("### Your question"))
        XCTAssertFalse(body.contains("Steps to reproduce"))
    }

    func test_defaultLabelsByKind() {
        XCTAssertEqual(BodyTemplates.defaultLabels(for: .bug), ["bug"])
        XCTAssertEqual(BodyTemplates.defaultLabels(for: .featureRequest), ["enhancement"])
        XCTAssertEqual(BodyTemplates.defaultLabels(for: .question), ["question"])
    }
}
