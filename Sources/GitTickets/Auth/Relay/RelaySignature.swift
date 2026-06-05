import Foundation
import CryptoKit

/// HMAC-SHA256 signature scheme used to authenticate requests to the relay.
///
/// Input is the bytes of `"<timestamp>.<body>"` (timestamp first, period
/// separator, then the JSON body as sent on the wire). Including the
/// timestamp protects against replay; the relay rejects timestamps outside
/// a 5-minute window.
///
/// Output is lowercase hex (`sha256=<hex>`). The relay's matching
/// verification in `/relay/vercel/api/_lib/hmac.ts` and
/// `/relay/cloudflare/src/lib/hmac.ts` must produce the same string for
/// the same inputs.
enum RelaySignature {

    /// Returns `"sha256=<lowercase hex>"`, the value of the
    /// `X-GitTickets-Signature` header.
    static func sign(timestamp: String, body: Data, secret: SharedSecret) -> String {
        var input = Data(timestamp.utf8)
        input.append(UInt8(ascii: "."))
        input.append(body)
        let mac = HMAC<SHA256>.authenticationCode(for: input, using: SymmetricKey(data: secret.bytes))
        return "sha256=" + Self.hex(mac)
    }

    /// Constant-time comparison helper used by tests; the live verification
    /// path runs server-side.
    ///
    /// The earlier `if count != count return false` short-circuit defeated
    /// the constant-time property — a length mismatch returned before the
    /// XOR loop ran. We now XOR over a fixed window (the length of the
    /// expected signature) and fold the length check into the result so
    /// every code path executes the same work regardless of input shape.
    static func verify(timestamp: String, body: Data, signature: String, secret: SharedSecret) -> Bool {
        let expectedBytes = Array(sign(timestamp: timestamp, body: body, secret: secret).utf8)
        let candidateBytes = Array(signature.utf8)
        var diff: UInt8 = expectedBytes.count == candidateBytes.count ? 0 : 1
        for i in 0..<expectedBytes.count {
            let lhs = expectedBytes[i]
            let rhs = i < candidateBytes.count ? candidateBytes[i] : 0
            diff |= lhs ^ rhs
        }
        return diff == 0
    }

    private static func hex(_ mac: HashedAuthenticationCode<SHA256>) -> String {
        mac.map { String(format: "%02x", $0) }.joined()
    }
}
