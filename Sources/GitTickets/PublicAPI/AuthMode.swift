import Foundation

/// Identifies a GitHub repository submissions should be posted to.
public struct RepoCoordinate: Sendable, Hashable {

    /// The GitHub owner (user or org login).
    public let owner: String

    /// The repository name.
    public let name: String

    /// Drives the wording of the mandatory privacy banner in the form.
    public let visibility: RepoVisibility

    public init(owner: String, name: String, visibility: RepoVisibility = .public) {
        self.owner = owner
        self.name = name
        self.visibility = visibility
    }
}

/// Whether the target repo is public-on-GitHub or private/internal.
///
/// Drives the wording of the mandatory privacy banner shown above the form.
/// Public repos warn that submissions are world-readable; private repos
/// soften to "visible to repo maintainers."
public enum RepoVisibility: Sendable, Hashable {
    /// World-readable on github.com.
    case `public`

    /// Restricted to repo collaborators / maintainers.
    case `private`
}

/// How the SDK authenticates to GitHub.
///
/// Two production modes plus a test-only mock.
///
/// ## Relay (default for consumer apps)
///
/// The developer deploys a tiny serverless relay (Vercel or Cloudflare Worker
/// template ships in `/relay/`) that holds a GitHub App installation token
/// scoped to `Issues: write` on exactly one repo. The SDK only ever talks to
/// the relay — the GitHub token never appears on the client.
///
/// End-users do NOT need a GitHub account.
///
/// ## Device Flow (opt-in for developer-targeted apps)
///
/// The end-user authenticates with their own GitHub account via the OAuth
/// Device Flow (ASWebAuthenticationSession). Issues are authored by that user.
///
/// **Limitations**: image attachments are not supported in Device Flow mode
/// (GitHub has no public attachment upload API and no relay-side storage is
/// available). Labels and assignees may silently fail for non-collaborator
/// users.
public enum AuthMode: Sendable {

    /// Default mode. Submit through a developer-hosted relay holding a
    /// GitHub App installation token.
    ///
    /// - Parameters:
    ///   - url: The base URL of the deployed relay (e.g. `https://reports.example.com`).
    ///   - sharedSecret: HMAC secret used to sign requests so the relay can
    ///     distinguish legitimate SDK traffic from arbitrary internet POSTs.
    case relay(url: URL, sharedSecret: SharedSecret)

    /// Opt-in mode. End-user authenticates to GitHub via OAuth Device Flow;
    /// submissions would be posted directly to the GitHub Issues API using
    /// the resulting user token (no relay needed).
    ///
    /// > Not yet implemented. ``GitTickets/submit(_:)`` throws
    /// > ``GitTicketsError/payloadInvalid(reason:)`` when this case is
    /// > active. Use ``relay(url:sharedSecret:)`` until the Device Flow
    /// > submitter ships.
    ///
    /// - Parameters:
    ///   - clientID: OAuth App client ID. See [Device Flow docs](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps#device-flow).
    ///   - scopes: OAuth scopes to request. Default `[.publicRepo]`.
    case deviceFlow(clientID: String, scopes: [DeviceFlowScope] = [.publicRepo])

    /// Reserved test-only slot for hosts that want to stand up
    /// ``Configuration`` without choosing a real auth mode.
    ///
    /// > Not dispatched in production: ``GitTickets/submit(_:)`` throws
    /// > ``GitTicketsError/payloadInvalid(reason:)`` when this case is
    /// > active. Useful when seeding `@Previews` or test fixtures that
    /// > never call `submit(_:)`.
    case mock
}

/// HMAC-SHA256 shared secret used to sign relay requests.
///
/// The same byte sequence must be configured in the relay's
/// `GITTICKETS_SHARED_SECRET` environment variable.
public struct SharedSecret: Sendable, Hashable {

    /// The raw secret bytes used as the HMAC key.
    public let bytes: Data

    /// Initialize from raw bytes.
    public init(bytes: Data) {
        self.bytes = bytes
    }

    /// Initialize from a base64-encoded string. Returns `nil` if the string
    /// is not valid base64.
    ///
    /// Trims surrounding whitespace and accepts embedded whitespace —
    /// matters because `vercel env pull`, 1Password copy, and most env-file
    /// readers leave a trailing newline that the default `Data(base64Encoded:)`
    /// would silently reject.
    public init?(base64: String) {
        let trimmed = base64.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = Data(base64Encoded: trimmed, options: [.ignoreUnknownCharacters]) else { return nil }
        self.bytes = data
    }

    /// Initialize from a hex-encoded string. Returns `nil` if the string is
    /// not valid hex or has an odd length. Accepts an optional `0x` prefix
    /// and tolerates surrounding whitespace.
    public init?(hex: String) {
        var trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("0x") || trimmed.hasPrefix("0X") {
            trimmed = String(trimmed.dropFirst(2))
        }
        guard trimmed.count.isMultiple(of: 2) else { return nil }
        var data = Data(capacity: trimmed.count / 2)
        var index = trimmed.startIndex
        while index < trimmed.endIndex {
            let next = trimmed.index(index, offsetBy: 2)
            guard let byte = UInt8(trimmed[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        self.bytes = data
    }
}

/// OAuth scopes for the Device Flow auth path.
public enum DeviceFlowScope: String, Sendable, Hashable {
    /// Read/write access to public repositories.
    case publicRepo = "public_repo"

    /// Full read/write access to all repositories the user can access.
    /// Required for posting to private repos.
    case repo
}
