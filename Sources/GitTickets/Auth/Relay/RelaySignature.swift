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
    static func verify(timestamp: String, body: Data, signature: String, secret: SharedSecret) -> Bool {
        let expected = sign(timestamp: timestamp, body: body, secret: secret)
        guard expected.count == signature.count else { return false }
        var diff: UInt8 = 0
        for (a, b) in zip(expected.utf8, signature.utf8) {
            diff |= a ^ b
        }
        return diff == 0
    }

    private static func hex(_ mac: HashedAuthenticationCode<SHA256>) -> String {
        Data(mac).map { String(format: "%02x", $0) }.joined()
    }
}
