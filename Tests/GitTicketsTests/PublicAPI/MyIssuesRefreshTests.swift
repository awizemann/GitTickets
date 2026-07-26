import Foundation
import XCTest
@testable import GitTickets

/// Covers the shortfall arithmetic that lets "My Reports" tell "you have no
/// reports" apart from "we could not find your reports".
///
/// The distinction is the whole point: a dropped label makes the backend answer
/// 200 with zero matches, which is indistinguishable from an empty history if
/// you only look at the returned array.
final class MyIssuesRefreshTests: XCTestCase {

    private func issue(_ number: Int) -> SubmittedIssue {
        SubmittedIssue(
            id: UUID(),
            issueNumber: number,
            issueURL: URL(string: "https://example.com/\(number)")!,
            title: "Report \(number)",
            createdAt: Date(timeIntervalSince1970: 1_750_000_000)
        )
    }

    /// The reported failure: submissions exist locally, the backend matches
    /// none of them. This must NOT read as an empty history.
    func test_allMissingWhenBackendMatchesNothing() {
        let refresh = MyIssuesRefresh(issues: [], requestedCount: 4)
        XCTAssertTrue(refresh.allMissing)
        XCTAssertEqual(refresh.unmatchedCount, 4)
    }

    /// A device that has genuinely never filed anything is NOT the failure
    /// case, and must keep the ordinary empty state.
    func test_noCachedSubmissionsIsNotAFault() {
        let refresh = MyIssuesRefresh(issues: [], requestedCount: 0)
        XCTAssertFalse(refresh.allMissing)
        XCTAssertEqual(refresh.unmatchedCount, 0)
    }

    /// A partial shortfall is ordinary — an issue can be deleted — so it must
    /// not trip the same signal as losing everything.
    func test_partialShortfallIsNotAllMissing() {
        let refresh = MyIssuesRefresh(issues: [issue(1), issue(2)], requestedCount: 3)
        XCTAssertFalse(refresh.allMissing)
        XCTAssertEqual(refresh.unmatchedCount, 1)
    }

    /// `allMissing` reports *that* nothing came back, never *why*.
    ///
    /// A user whose issues were all deleted and a user whose issues merely lost
    /// the label the backend finds them by produce **identical** results —
    /// telling them apart would need a per-issue existence probe the backend
    /// does not expose. This is pinned because the two cases call for opposite
    /// reassurances: an earlier build told the deleted-issues user "they
    /// haven't been lost", which was simply false.
    ///
    /// If you are here because you want `allMissing` to imply a cause: it
    /// cannot, and this test is why.
    func test_deletedIssuesAndDroppedLabelsAreIndistinguishable() {
        let allIssuesDeleted = MyIssuesRefresh(issues: [], requestedCount: 3)
        let labelDroppedFromAll = MyIssuesRefresh(issues: [], requestedCount: 3)

        XCTAssertEqual(allIssuesDeleted, labelDroppedFromAll)
        XCTAssertTrue(allIssuesDeleted.allMissing)
        XCTAssertTrue(labelDroppedFromAll.allMissing)
    }

    func test_fullMatchHasNoShortfall() {
        let refresh = MyIssuesRefresh(issues: [issue(1), issue(2)], requestedCount: 2)
        XCTAssertFalse(refresh.allMissing)
        XCTAssertEqual(refresh.unmatchedCount, 0)
    }

    /// Defensive: a backend returning MORE than was asked for must not produce
    /// a negative count that reads as a shortfall elsewhere.
    func test_unmatchedCountNeverNegative() {
        let refresh = MyIssuesRefresh(issues: [issue(1), issue(2), issue(3)], requestedCount: 2)
        XCTAssertEqual(refresh.unmatchedCount, 0)
        XCTAssertFalse(refresh.allMissing)
    }
}
