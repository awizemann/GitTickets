import Foundation

/// Wire-format DTOs for the developer-hosted relay.
///
/// These types are the contract with the Vercel and Cloudflare templates
/// in `/relay/`. Changing the JSON shape here is a breaking change for
/// deployed relays — bump the SDK major version + relay template major
/// version together.

// MARK: - POST /report

/// Request body sent to `POST /report`.
///
/// Note on omitted fields:
/// - `kind` is not sent on the wire — `labels` already encodes it via
///   ``BodyTemplates/defaultLabels(for:)``.
/// - `userAgent` is not sent in the body — the HTTP `User-Agent` header is
///   the single source of truth; the relay reads it from there.
struct RelayReportRequest: Codable, Sendable, Hashable {
    let schemaVersion: Int
    let title: String
    let body: String
    let labels: [String]
    let submissionID: String
    let deviceID: String
    let attachmentURLs: [String]

    /// Wire-format schema version. Bumped only on breaking changes.
    static let currentSchemaVersion = 1

    init(
        title: String,
        body: String,
        labels: [String],
        submissionID: String,
        deviceID: String,
        attachmentURLs: [String]
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.title = title
        self.body = body
        self.labels = labels
        self.submissionID = submissionID
        self.deviceID = deviceID
        self.attachmentURLs = attachmentURLs
    }
}

/// Response from `POST /report` on success (HTTP 200).
struct RelayReportResponse: Codable, Sendable, Hashable {
    let issueNumber: Int
    let issueURL: String
    let title: String
    let createdAt: String  // ISO 8601 with fractional seconds, UTC
    /// Labels GitHub actually applied to the issue. Compared against the
    /// requested labels so the SDK can surface drops via
    /// ``SubmittedIssue/missingLabels``.
    let appliedLabels: [String]?
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

    /// Wire-format schema version for the `/my-issues` endpoint. Versioned
    /// independently of ``RelayReportRequest`` so the two endpoints can
    /// evolve without forcing simultaneous bumps.
    static let currentSchemaVersion = 1

    init(submissionIDs: [String], deviceID: String) {
        self.schemaVersion = Self.currentSchemaVersion
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

// MARK: - POST /comments

/// Request body sent to `POST /comments`. The relay proxies to GitHub's
/// `GET /repos/:owner/:name/issues/:n/comments`.
struct CommentsRequest: Codable, Sendable, Hashable {
    let schemaVersion: Int
    let issueNumber: Int
    let deviceID: String

    /// Wire-format schema version for the `/comments` endpoint. Versioned
    /// independently of the other endpoints so they can evolve apart.
    static let currentSchemaVersion = 1

    init(issueNumber: Int, deviceID: String) {
        self.schemaVersion = Self.currentSchemaVersion
        self.issueNumber = issueNumber
        self.deviceID = deviceID
    }
}

/// Response from `POST /comments`. Ordered oldest comment first.
struct CommentsResponse: Codable, Sendable, Hashable {
    let comments: [CommentsItem]
}

struct CommentsItem: Codable, Sendable, Hashable {
    let id: Int
    let author: String
    let body: String
    let createdAt: String  // ISO 8601 with fractional seconds, UTC
}

// MARK: - Generic error

/// Relay error envelope, returned with non-2xx responses when the relay
/// chooses to include one.
struct RelayErrorEnvelope: Codable, Sendable, Hashable {
    let error: String
    let message: String?
    /// Optional server-communicated byte limit for 413 responses. The SDK
    /// surfaces this via ``GitTicketsError/attachmentTooLarge(byteLimit:)``
    /// instead of a hardcoded constant so operators that raise the relay's
    /// limit don't end up with clients that lie about the cap.
    let byteLimit: Int?
}

// MARK: - JSON helpers

enum RelayJSON {
    /// Encoder used for relay request bodies.
    ///
    /// `.sortedKeys` is critical for HMAC stability — the signature is
    /// computed over the encoded bytes, so the dictionary key order must
    /// be deterministic across runs.
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()
}
