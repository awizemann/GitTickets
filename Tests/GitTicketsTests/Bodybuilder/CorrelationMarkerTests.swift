import XCTest
@testable import GitTickets

final class CorrelationMarkerTests: XCTestCase {

    func test_renderProducesStableFormat() {
        let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        XCTAssertEqual(
            CorrelationMarker.render(for: id),
            "<!-- gittickets-id: 11111111-2222-3333-4444-555555555555 -->"
        )
    }

    func test_roundTrip() {
        let id = UUID()
        let body = "User body text.\n\n" + CorrelationMarker.render(for: id)
        XCTAssertEqual(CorrelationMarker.extract(from: body), id)
    }

    func test_extractFromBodyWithSurroundingMarkdown() {
        let id = UUID()
        let body = """
        # Bug report

        Steps to reproduce: tap the button.

        ---

        ### Diagnostics
        ```
        OS: iOS 17.5
        ```

        \(CorrelationMarker.render(for: id))
        """
        XCTAssertEqual(CorrelationMarker.extract(from: body), id)
    }

    func test_extractWithoutWhitespace() {
        let id = UUID()
        let body = "<!--gittickets-id:\(id.uuidString)-->"
        XCTAssertEqual(CorrelationMarker.extract(from: body), id)
    }

    func test_extractIgnoresOtherHtmlComments() {
        let id = UUID()
        let body = """
        <!-- some other comment -->
        Body text.
        <!-- gittickets-id: \(id.uuidString) -->
        """
        XCTAssertEqual(CorrelationMarker.extract(from: body), id)
    }

    func test_extractReturnsNilWhenAbsent() {
        XCTAssertNil(CorrelationMarker.extract(from: "Plain body, no marker."))
    }

    func test_extractReturnsNilForMalformedUUID() {
        let body = "<!-- gittickets-id: 11111111-2222-3333-4444-XXXXXXXXXXXX -->"
        XCTAssertNil(CorrelationMarker.extract(from: body))
    }

    func test_extractReturnsFirstMarkerWhenMultiple() {
        let first = UUID()
        let second = UUID()
        let body = """
        \(CorrelationMarker.render(for: first))

        \(CorrelationMarker.render(for: second))
        """
        XCTAssertEqual(CorrelationMarker.extract(from: body), first)
    }
}
