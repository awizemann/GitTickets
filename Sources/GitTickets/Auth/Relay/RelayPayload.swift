import Foundation

/// Wire-format DTOs for the developer-hosted relay.
///
/// These types are the contract with the Vercel and Cloudflare templates
/// in `/relay/`. Changing the JSON shape here is a breaking change for
/// deployed relays — bump the SDK major version + relay template major
/// version together.

// MARK: - POST /report

/// Request body sent to `POST /report`.
struct RelayReportRequest: Codable, Sendable, Hashable {
    let schemaVersion: Int
    let title: String
    let body: String
    let kind: String
    let labels: [String]
    let submissionID: String
    let deviceID: String
    let attachmentURLs: [String]
    let userAgent: String

    /// Wire-format schema version. Bumped only on breaking changes.
    static let currentSchemaVersion = 1

    init(
        title: String,
        body: String,
        kind: String,
        labels: [String],
        submissionID: String,
        deviceID: String,
        attachmentURLs: [String],
        userAgent: String
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.title = title
        self.body = body
        self.kind = kind
        self.labels = labels
        self.submissionID = submissionID
        self.deviceID = deviceID
        self.attachmentURLs = attachmentURLs
        self.userAgent = userAgent
    }
}

/// Response from `POST /report` on success (HTTP 200).
struct RelayReportResponse: Codable, Sendable, Hashable {
    let issueNumber: Int
    let issueURL: String
    let title: String
    let createdAt: String  // ISO 8601 with fractional seconds, UTC
}

// MARK: - POST /attachment

/// Response from `POST /attachment` (multipart) on success (HTTP 200).
struct RelayAttachmentResponse: Codable, Sendable, Hashable {
    let url: String
    let mimeType: String
    let byteCount: Int
}

// MARK: - POST /my-issues

/// Request body sent to `POST /my-issues`. The relay scans GitHub for issues
/// labelled `gittickets` and matches embedded `<!-- gittickets-id: -->`
/// markers against this list.
struct MyIssuesRequest: Codable, Sendable, Hashable {
    let schemaVersion: Int
    let submissionIDs: [String]
    let deviceID: String

    init(submissionIDs: [String], deviceID: String) {
        self.schemaVersion = RelayReportRequest.currentSchemaVersion
        self.submissionIDs = submissionIDs
        self.deviceID = deviceID
    }
}

/// Response from `POST /my-issues`. One entry per matched submission.
struct MyIssuesResponse: Codable, Sendable, Hashable {
    let issues: [MyIssuesItem]
}

struct MyIssuesItem: Codable, Sendable, Hashable {
    let submissionID: String
    let issueNumber: Int
    let issueURL: String
    let title: String
    let state: String  // "open" | "closed"
    let createdAt: String
    let updatedAt: String
    let replyCount: Int
    let latestReplyAt: String?
}

// MARK: - Generic error

/// Relay error envelope, returned with non-2xx responses when the relay
/// chooses to include one.
struct RelayErrorEnvelope: Codable, Sendable, Hashable {
    let error: String
    let message: String?
}

// MARK: - JSON helpers

enum RelayJSON {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
