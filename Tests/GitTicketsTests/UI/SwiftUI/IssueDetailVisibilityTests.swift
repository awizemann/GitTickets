import XCTest
import SwiftUI
@testable import GitTickets

/// Private repos never surface GitHub links or GitHub-pointing copy in the
/// "My Reports" detail screen — reporters would hit a 404 / login wall.
@MainActor
final class IssueDetailVisibilityTests: XCTestCase {

    private let url = URL(string: "https://github.com/alanw/GitTickets/issues/42")!

    private func configuration(_ visibility: RepoVisibility) -> Configuration {
        Configuration(
            repo: RepoCoordinate(owner: "alanw", name: "GitTickets", visibility: visibility),
            auth: .mock
        )
    }

    // MARK: - RepoVisibility.isPublic

    func test_isPublic_publicRepo() {
        XCTAssertTrue(RepoVisibility.isPublic(configuration(.public)))
    }

    func test_isPublic_privateRepo() {
        XCTAssertFalse(RepoVisibility.isPublic(configuration(.private)))
    }

    func test_isPublic_nilConfigurationBehavesAsPublic() {
        XCTAssertTrue(RepoVisibility.isPublic(nil))
    }

    // MARK: - IssueStateCard

    private func card(_ kind: IssueStateCard.Kind, showsGitHubLink: Bool) -> IssueStateCard {
        IssueStateCard(kind, theme: .default, showsGitHubLink: showsGitHubLink, retry: {})
    }

    func test_stateCard_public_rendersLinkToIssue() {
        XCTAssertEqual(card(.noReplies(issueURL: url), showsGitHubLink: true).linkURL, url)
        XCTAssertEqual(card(.error(message: "offline", issueURL: url), showsGitHubLink: true).linkURL, url)
    }

    func test_stateCard_private_rendersNoLink() {
        XCTAssertNil(card(.noReplies(issueURL: url), showsGitHubLink: false).linkURL)
        XCTAssertNil(card(.error(message: "offline", issueURL: url), showsGitHubLink: false).linkURL)
    }

    func test_stateCard_noReplies_public_showsLinkRow() {
        let card = card(.noReplies(issueURL: url), showsGitHubLink: true)
        XCTAssertTrue(card.hasActions)
    }

    func test_stateCard_noReplies_private_dropsActionRowEntirely() {
        let card = card(.noReplies(issueURL: url), showsGitHubLink: false)
        XCTAssertFalse(card.hasActions)
        XCTAssertFalse(card.message.contains("GitHub"))
    }

    func test_stateCard_error_public_keepsGitHubCopy() {
        let card = card(.error(message: "offline", issueURL: url), showsGitHubLink: true)
        XCTAssertTrue(card.hasActions)
        XCTAssertEqual(
            card.message,
            "Your report is saved above. Replies live on GitHub — check your connection and try again."
        )
    }

    func test_stateCard_error_private_keepsRetryWithNeutralCopy() {
        let card = card(.error(message: "offline", issueURL: url), showsGitHubLink: false)
        XCTAssertTrue(card.hasActions, "Retry must survive on private repos")
        XCTAssertEqual(card.message, "Your report is saved above. Check your connection and try again.")
    }

    // MARK: - IssueHeader

    private var issue: SubmittedIssue {
        SubmittedIssue(
            id: UUID(),
            issueNumber: 42,
            issueURL: url,
            title: "Crash on launch",
            createdAt: Date(timeIntervalSince1970: 1_750_000_000)
        )
    }

    func test_header_public_rendersLinkToIssue() {
        XCTAssertEqual(IssueHeader(issue: issue, kind: nil, theme: .default, showsGitHubLink: true).linkURL, url)
    }

    func test_header_private_rendersNoLink() {
        XCTAssertNil(IssueHeader(issue: issue, kind: nil, theme: .default, showsGitHubLink: false).linkURL)
    }

    // MARK: - IssueDetailView wiring (configuration → the subviews it builds)

    private func detail(_ configuration: Configuration?) -> IssueDetailView {
        IssueDetailView(issue: issue, cachedReport: nil, configuration: configuration, loadComments: { [] })
    }

    func test_detail_publicRepo_everyLinkPointsAtIssue() {
        for config in [configuration(.public), nil] {
            let view = detail(config)
            XCTAssertEqual(view.header.linkURL, url)
            XCTAssertEqual(view.stateCard(.noReplies(issueURL: url)).linkURL, url)
            XCTAssertEqual(view.stateCard(.error(message: "offline", issueURL: url)).linkURL, url)
        }
    }

    func test_detail_privateRepo_hidesEveryLink() {
        let view = detail(configuration(.private))
        XCTAssertNil(view.header.linkURL)
        XCTAssertNil(view.stateCard(.noReplies(issueURL: url)).linkURL)
        XCTAssertNil(view.stateCard(.error(message: "offline", issueURL: url)).linkURL)
        XCTAssertTrue(view.stateCard(.error(message: "offline", issueURL: url)).hasActions,
                      "Retry must survive on private repos")
    }
}
