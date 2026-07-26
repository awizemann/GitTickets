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
    /// submissions are posted directly to the GitHub Issues API using the
    /// resulting user token (no relay needed). Issues are authored by the
    /// end-user, not the developer.
    ///
    /// Image attachments are NOT supported in this mode — GitHub has no public
    /// attachment upload API and Device Flow has no relay-side storage.
    /// Submissions with attachments throw ``GitTicketsError/attachmentNotSupportedInDeviceFlow``.
    ///
    /// Submissions before the user has completed the OAuth flow throw
    /// ``GitTicketsError/deviceFlowNotAuthorized``. The form must drive
    /// `DeviceFlowCoordinator` and persist the resulting token via
    /// `TokenStore` before calling ``GitTickets/submit(_:)``.
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
    /// is empty, padding-only, or not valid base64.
    ///
    /// Trims surrounding whitespace — matters because `vercel env pull`,
    /// 1Password copy, and most env-file readers leave a trailing newline
    /// that the default `Data(base64Encoded:)` would silently reject.
    /// Whitespace *inside* the payload is still rejected (see the note below
    /// on `.ignoreUnknownCharacters`): a mangled secret must fail loudly
    /// rather than decode to some other key.
    public init?(base64: String) {
        let trimmed = base64.trimmingCharacters(in: .whitespacesAndNewlines)
        // No `.ignoreUnknownCharacters`: with that option, "!!!" decodes to
        // empty Data and slips through as a 0-byte secret. Trimming alone
        // handles the env-pull trailing-newline case the option was added for.

        // Reject a payload that starts with padding. `Data(base64Encoded:)`
        // decodes "====" (and "========", …) to a single 0x00 byte, which is
        // non-empty and therefore sails past the `!data.isEmpty` guard below
        // as a 1-byte all-zero HMAC key. Every all-padding string starts with
        // "=", so this one check closes the whole family.
        guard trimmed.first != "=" else { return nil }
        guard let data = Data(base64Encoded: trimmed), !data.isEmpty else { return nil }
        self.bytes = data
    }

    /// Initialize from a hex-encoded string. Returns `nil` if the string is
    /// empty, has an odd number of digits, or contains anything outside
    /// `0-9a-fA-F`. Accepts an optional `0x`/`0X` prefix and tolerates
    /// surrounding whitespace; whitespace or a sign character *inside* the
    /// payload is rejected rather than skipped.
    public init?(hex: String) {
        var trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("0x") || trimmed.hasPrefix("0X") {
            trimmed = String(trimmed.dropFirst(2))
        }
        // Reject empty up front, matching `init?(base64:)`. Without this,
        // "", "   ", and "0x" all satisfy `isMultiple(of: 2)` with zero
        // digits and produce a live 0-byte HMAC key — a secret that signs
        // every request identically and is silently wrong rather than
        // cleanly nil.
        guard !trimmed.isEmpty else { return nil }

        // Validate the alphabet before pair-parsing. `UInt8(_:radix:)` accepts
        // a leading "+" sign, so "+1+1" would otherwise parse as the two bytes
        // 0x01 0x01 — a well-formed key derived from a string that is not hex
        // at all. Restricting to ASCII 0-9/a-f/A-F also excludes Unicode
        // look-alike digits, which the parser rejects anyway; belt and braces.
        let isASCIIHexDigit: (UInt8) -> Bool = { byte in
            (0x30...0x39).contains(byte)      // 0-9
                || (0x41...0x46).contains(byte)  // A-F
                || (0x61...0x66).contains(byte)  // a-f
        }
        guard trimmed.utf8.allSatisfy(isASCIIHexDigit) else { return nil }

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

// MARK: - Reading the shared secret out of Info.plist

extension SharedSecret {

    /// How the string stored in Info.plist is encoded.
    ///
    /// There is deliberately no `.autoDetect`. See
    /// ``SharedSecret/init(infoPlistKey:encoding:bundle:)`` for why.
    public enum Encoding: Sendable, Hashable {
        /// Hex digits, optionally `0x`-prefixed. Even number of digits.
        case hex

        /// Standard base64 with padding.
        case base64
    }

    /// Read the shared secret from a key in the app bundle's `Info.plist`.
    ///
    /// This exists so the secret does not have to be a literal in your source.
    /// The intended setup is an `.xcconfig` that is **gitignored**, referenced
    /// from an `Info.plist` build setting:
    ///
    /// ```
    /// // Secrets.xcconfig — listed in .gitignore
    /// GITTICKETS_SHARED_SECRET = 8f14e45fceea167a5a36dedd4bea2543
    /// ```
    ///
    /// ```xml
    /// <!-- Info.plist -->
    /// <key>GitTicketsSharedSecret</key>
    /// <string>$(GITTICKETS_SHARED_SECRET)</string>
    /// ```
    ///
    /// ```swift
    /// guard let secret = SharedSecret(
    ///     infoPlistKey: "GitTicketsSharedSecret",
    ///     encoding: .hex
    /// ) else {
    ///     // Misconfigured build. Fail loudly here — see "Handling nil" below.
    ///     fatalError("GitTicketsSharedSecret missing or not valid hex")
    /// }
    /// let auth = AuthMode.relay(url: relayURL, sharedSecret: secret)
    /// ```
    ///
    /// ## This does NOT make the secret secret
    ///
    /// `Info.plist` ships as **plaintext inside the `.app` bundle**. Anyone
    /// who can download your app can read it in one command:
    ///
    /// ```sh
    /// plutil -p MyApp.app/Contents/Info.plist
    /// ```
    ///
    /// No obfuscation, no entitlement, no code signing check stands between an
    /// attacker and this value. What this initializer buys you is that the
    /// secret is not in **git** — which is the difference between "leaked to
    /// anyone who clones a public repo, forever, across every historical
    /// commit" and "extractable by someone who bothers to crack open the
    /// bundle."
    ///
    /// The relay shared secret exists to gate *casual* abuse: it stops
    /// arbitrary internet POSTs from filing issues in your repo. It is not a
    /// credential guarding anything of value, and it must not be treated as
    /// one. The GitHub token stays on the relay precisely because the client
    /// side cannot keep a secret. Treat this value as "moderately
    /// confidential, rotatable" — the same posture
    /// `docs/threat-model.md` describes under "Compromise of the shared
    /// secret in your build pipeline" — and assume you will rotate it at some
    /// point. Do not put anything else in `Info.plist` on the strength of
    /// this API existing.
    ///
    /// ## Why `encoding` has no default and is never sniffed
    ///
    /// ``SharedSecret`` accepts both hex and base64, and plenty of strings are
    /// valid in *both* with different byte results. `"deadbeef"` is 4 bytes as
    /// hex (`de ad be ef`) and 6 completely different bytes as base64
    /// (`75 e6 9d 6d e7 9f`). Auto-detection would pick one, derive a
    /// perfectly well-formed key that happens to be the wrong one, and the
    /// only symptom would be `401 signatureMismatch` from the relay with no
    /// hint as to why. Stating the encoding is one word of typing and removes
    /// that failure mode entirely.
    ///
    /// ## Info.plist only — no environment variables
    ///
    /// There is deliberately no environment-variable equivalent. A shipped
    /// `.app` launched from Finder, Dock, or Spotlight inherits no useful
    /// environment: `getenv` only sees what you set when launching from Xcode
    /// or a terminal. An env-var path would therefore work perfectly for you
    /// during development and return `nil` for every one of your actual
    /// users. That is not an omission to be filled in later; shipping it would
    /// be a trap.
    ///
    /// ## Handling nil
    ///
    /// `nil` means one of exactly two things, and they are both build
    /// misconfigurations rather than runtime conditions:
    ///
    /// 1. **The key is absent** — no `infoPlistKey` entry in the bundle's
    ///    `Info.plist`, or the entry is not a string (a number, array, or
    ///    dictionary value is treated as absent). Typically a missing
    ///    `Info.plist` key or an `.xcconfig` that was not wired to the
    ///    target.
    /// 2. **The key is present but not decodable in `encoding`** — for
    ///    `.hex`, a non-hex character or an odd digit count; for `.base64`,
    ///    an invalid, unpadded, or padding-only payload. An empty or
    ///    whitespace-only value also lands here — this initializer never
    ///    yields a zero-length key. The classic cause is an unresolved build setting:
    ///    the literal text `$(GITTICKETS_SHARED_SECRET)` decodes as neither.
    ///
    /// Both are conditions you want to discover on the first launch of a debug
    /// build, not from a support ticket. The recommended pattern is to fail
    /// hard at configuration time (`fatalError`, `preconditionFailure`, or a
    /// thrown error from your own setup function) rather than fall back to a
    /// literal or silently skip calling ``GitTickets/configure(_:)``. A crash
    /// on launch is loud and immediate; a relay that rejects every submission
    /// in production is neither.
    ///
    /// If you would rather degrade than crash, hide the report entry point
    /// when this returns `nil` — do not configure ``AuthMode/relay(url:sharedSecret:)``
    /// with a placeholder.
    ///
    /// - Parameters:
    ///   - infoPlistKey: The `Info.plist` key holding the encoded secret.
    ///   - encoding: How that string is encoded. Required — see above.
    ///   - bundle: The bundle to read from. Defaults to `.main`, which is the
    ///     host app. Pass an explicit bundle in tests, or if the value lives
    ///     in a framework's `Info.plist` rather than the app's.
    /// - Returns: `nil` if the key is absent/non-string, or present but not
    ///   decodable as `encoding`.
    public init?(infoPlistKey: String, encoding: Encoding, bundle: Bundle = .main) {
        // `infoDictionary` rather than `object(forInfoDictionaryKey:)`: the
        // latter consults `InfoPlist.strings` and can return a *localized*
        // override of the key. For a signing key we want the raw plist value
        // with no indirection that could hand back a different string.
        guard let raw = bundle.infoDictionary?[infoPlistKey] as? String else {
            // Covers both "key absent" and "key present but not a string".
            // A number, array, or dictionary is a misconfiguration, and there
            // is no defensible coercion — `42` is not a secret, and
            // stringifying it would invent a key.
            return nil
        }

        // Delegate to the existing decoders instead of reimplementing them:
        // they already handle the trailing newline that `vercel env pull` and
        // password-manager copy leave behind, the `0x` prefix, and rejecting
        // whitespace embedded in the payload.
        let decoded: SharedSecret?
        switch encoding {
        case .hex:
            decoded = SharedSecret(hex: raw)
        case .base64:
            decoded = SharedSecret(base64: raw)
        }

        // Belt-and-braces: a 0-byte key is a valid `Data` but a broken secret,
        // and it would sign every request identically. Both decoders reject
        // empty input already; this guard means a future change to either one
        // cannot leak an empty key through this path.
        guard let decoded, !decoded.bytes.isEmpty else { return nil }
        self = decoded
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
