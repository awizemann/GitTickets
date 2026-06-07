import Foundation

// MARK: - GitHub Device Flow wire format
//
// Two endpoints on github.com (NOT api.github.com) and one on api.github.com:
//
//   POST https://github.com/login/device/code          → DeviceCodeRequest / DeviceCodeResponse
//   POST https://github.com/login/oauth/access_token   → AccessTokenRequest / AccessTokenResponse
//   POST https://api.github.com/repos/:owner/:name/issues → CreateIssueRequest / CreateIssueResponse
//
// Wire docs: https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps#device-flow
//
// GitHub returns errors as `{ "error": "...", "error_description": "..." }` with HTTP 200 on the
// token endpoint — the JSON body is the only source of truth, not the status code. Both payloads
// (success + error) get decoded against `AccessTokenResponse`.

/// `POST /login/device/code` request body. Sent as `application/x-www-form-urlencoded` because
/// GitHub's device-code endpoint does not accept JSON.
struct DeviceCodeRequest {
    let clientID: String
    let scope: String
}

/// `POST /login/device/code` success response.
struct DeviceCodeResponse: Decodable, Sendable, Equatable {
    let deviceCode: String
    let userCode: String
    let verificationURI: String
    let verificationURIComplete: String?
    let expiresIn: Int
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case verificationURIComplete = "verification_uri_complete"
        case expiresIn = "expires_in"
        case interval
    }
}

/// `POST /login/oauth/access_token` poll body.
struct AccessTokenRequest {
    let clientID: String
    let deviceCode: String
    static let grantType = "urn:ietf:params:oauth:grant-type:device_code"
}

/// `POST /login/oauth/access_token` response. GitHub returns either the success shape
/// (`access_token` set) OR the error shape (`error` set) — never both — with HTTP 200 in both
/// cases. The poll loop branches on which field is present.
struct AccessTokenResponse: Decodable, Sendable, Equatable {
    let accessToken: String?
    let tokenType: String?
    let scope: String?
    let error: String?
    let errorDescription: String?
    let interval: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope
        case error
        case errorDescription = "error_description"
        case interval
    }
}

/// `POST /repos/:owner/:name/issues` body. GitHub accepts more fields than this (assignees,
/// milestone, etc.) but we only need title/body/labels for v1.
struct CreateIssueRequest: Encodable {
    let title: String
    let body: String
    let labels: [String]
}

/// `POST /repos/:owner/:name/issues` 201 response. Only the fields we surface — GitHub's payload
/// is much larger but we don't need the rest.
struct CreateIssueResponse: Decodable, Sendable {
    let number: Int
    let htmlURL: String
    let title: String
    let createdAt: String
    let labels: [Label]

    struct Label: Decodable, Sendable {
        let name: String
    }

    enum CodingKeys: String, CodingKey {
        case number
        case htmlURL = "html_url"
        case title
        case createdAt = "created_at"
        case labels
    }
}

/// GitHub error envelope returned on 4xx/5xx from the Issues API. The token endpoint uses the
/// inline-on-200 form above; the Issues API uses this wrapper with a non-2xx status.
struct GitHubErrorEnvelope: Decodable, Sendable {
    let message: String?
    let documentationURL: String?

    enum CodingKeys: String, CodingKey {
        case message
        case documentationURL = "documentation_url"
    }
}

/// Shared JSON coders for the Device Flow path. ISO8601 dates use the relay's parser since
/// GitHub returns the same format.
enum DeviceFlowJSON {
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }()
}

/// Encodes a `DeviceCodeRequest` / `AccessTokenRequest` as form-urlencoded bytes. RFC 3986
/// unreserved set only — anything else gets percent-encoded — so a `+` in a value (legal in
/// scope names? no — but defense in depth) doesn't get decoded back as a space on the server.
enum FormURLEncoded {
    static func encode(_ pairs: [(String, String)]) -> Data {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let body = pairs.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
        return Data(body.utf8)
    }
}
