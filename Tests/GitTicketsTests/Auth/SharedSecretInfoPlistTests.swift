import XCTest
@testable import GitTickets

/// Tests for ``SharedSecret/init(infoPlistKey:encoding:bundle:)``.
///
/// ## Why these build a bundle on disk
///
/// The running test bundle cannot carry the key. `swift test` produces
/// `GitTicketsPackageTests.xctest` with a `Contents/MacOS/` directory and **no
/// `Info.plist` whatsoever** — verified on this toolchain (Swift 6.3.3) — so
/// `Bundle(for:)` on a test class has a nil `infoDictionary` and there is
/// nothing to add keys to. `Package.swift`'s `resources:` copies files *into* a
/// resource bundle; it does not merge keys into a test bundle's `Info.plist`,
/// and SwiftPM exposes no manifest hook that would.
///
/// So rather than mock `Bundle` — which would test a protocol shim instead of
/// the real `Bundle` lookup an adopter gets — each test writes a genuine bundle
/// directory into a temp dir and loads it with `Bundle(url:)`. That exercises
/// the real Foundation `Info.plist` read path, including the real behaviour for
/// non-string plist values (which a hand-rolled `[String: String]` fake could
/// not even represent). Bundles are given a UUID path so CFBundle's path-keyed
/// cache never hands back a previous test's bundle.
final class SharedSecretInfoPlistTests: XCTestCase {

    // "deadbeef" is the load-bearing fixture: it is valid hex AND valid
    // base64, and the two decode to entirely different keys. Any accidental
    // encoding sniffing shows up as one of these two expectations failing.
    private static let ambiguous = "deadbeef"
    private static let ambiguousAsHex = Data([0xde, 0xad, 0xbe, 0xef])
    private static let ambiguousAsBase64 = Data([0x75, 0xe6, 0x9d, 0x6d, 0xe7, 0x9f])

    private let key = "GitTicketsSharedSecret"
    private var scratch: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        scratch = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("SharedSecretInfoPlistTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let scratch { try? FileManager.default.removeItem(at: scratch) }
        scratch = nil
        try super.tearDownWithError()
    }

    /// Writes a real `.bundle` on disk carrying `entries` in its `Info.plist`
    /// and returns the loaded `Bundle`.
    private func makeBundle(_ entries: [String: Any]) throws -> Bundle {
        let bundleURL = scratch
            .appendingPathComponent("Host-\(UUID().uuidString).bundle", isDirectory: true)
        // Flat layout (`Foo.bundle/Info.plist`). CFBundle accepts it on macOS
        // as well as iOS, so the fixture works whichever platform the suite
        // runs on; the `Contents/` layout would be macOS-only.
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        var info: [String: Any] = [
            "CFBundleIdentifier": "com.gittickets.tests.\(UUID().uuidString)",
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundlePackageType": "BNDL",
        ]
        for (k, v) in entries { info[k] = v }

        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: bundleURL.appendingPathComponent("Info.plist"))

        let bundle = try XCTUnwrap(Bundle(url: bundleURL), "Foundation refused to load the fixture bundle")
        // Guard the harness itself: if this ever stops reading back, every
        // "returns nil" assertion below would pass for the wrong reason.
        XCTAssertNotNil(bundle.infoDictionary, "fixture bundle has no readable Info.plist")
        return bundle
    }

    private func secret(_ value: Any, _ encoding: SharedSecret.Encoding) throws -> SharedSecret? {
        let bundle = try makeBundle([key: value])
        return SharedSecret(infoPlistKey: key, encoding: encoding, bundle: bundle)
    }

    // MARK: - Key present and valid

    func test_hexKeyPresentAndValid() throws {
        let secret = try secret("8f14e45fceea167a5a36dedd4bea2543", .hex)
        XCTAssertEqual(secret?.bytes.count, 16)
        XCTAssertEqual(secret?.bytes.first, 0x8f)
        XCTAssertEqual(secret?.bytes.last, 0x43)
    }

    func test_base64KeyPresentAndValid() throws {
        // 32 random-looking bytes, the size the relay template documents.
        let raw = Data((0..<32).map { UInt8($0 &* 7 &+ 3) })
        let secret = try secret(raw.base64EncodedString(), .base64)
        XCTAssertEqual(secret?.bytes, raw)
    }

    func test_hexKeyToleratesLeading0xPrefix() throws {
        XCTAssertEqual(try secret("0xdeadbeef", .hex)?.bytes, Self.ambiguousAsHex)
    }

    /// The `.xcconfig` → `Info.plist` path can pick up a trailing newline from
    /// `vercel env pull` or a password-manager copy. Both decoders trim.
    func test_toleratesTrailingNewlineFromEnvTooling() throws {
        XCTAssertEqual(try secret("deadbeef\n", .hex)?.bytes, Self.ambiguousAsHex)
        XCTAssertEqual(try secret("3q2+7w==\n", .base64)?.bytes, Self.ambiguousAsHex)
    }

    // MARK: - No encoding sniffing

    /// The whole reason `encoding` is required. The same plist value must
    /// produce two different keys depending on the stated encoding — if either
    /// assertion fails, something is guessing.
    func test_sameValueDecodesDifferentlyPerStatedEncoding() throws {
        XCTAssertEqual(try secret(Self.ambiguous, .hex)?.bytes, Self.ambiguousAsHex)
        XCTAssertEqual(try secret(Self.ambiguous, .base64)?.bytes, Self.ambiguousAsBase64)
        XCTAssertNotEqual(Self.ambiguousAsHex, Self.ambiguousAsBase64)
    }

    // MARK: - Key absent

    func test_keyAbsentReturnsNil() throws {
        let bundle = try makeBundle([:])
        XCTAssertNil(SharedSecret(infoPlistKey: key, encoding: .hex, bundle: bundle))
        XCTAssertNil(SharedSecret(infoPlistKey: key, encoding: .base64, bundle: bundle))
    }

    func test_differentKeyPresentReturnsNil() throws {
        let bundle = try makeBundle(["SomeOtherKey": "deadbeef"])
        XCTAssertNil(SharedSecret(infoPlistKey: key, encoding: .hex, bundle: bundle))
    }

    // MARK: - Key present but not decodable in the stated encoding

    func test_hexKeyWithNonHexCharacterReturnsNil() throws {
        XCTAssertNil(try secret("zzzz", .hex))
    }

    func test_hexKeyWithOddDigitCountReturnsNil() throws {
        XCTAssertNil(try secret("abc", .hex))
    }

    func test_base64KeyWithInvalidPayloadReturnsNil() throws {
        XCTAssertNil(try secret("!!!", .base64))
    }

    func test_base64KeyWithBadPaddingReturnsNil() throws {
        // 6 base64 characters: not a whole number of quantums.
        XCTAssertNil(try secret("3q2+7w", .base64))
    }

    /// A value valid in the *other* encoding must still fail in the stated one.
    func test_base64OnlyValueRejectedAsHex() throws {
        XCTAssertNil(try secret("3q2+7w==", .hex))
    }

    /// The most common real misconfiguration: the build setting never resolved,
    /// so the literal `$(...)` text ships in Info.plist.
    func test_unresolvedBuildSettingLiteralReturnsNil() throws {
        XCTAssertNil(try secret("$(GITTICKETS_SHARED_SECRET)", .hex))
        XCTAssertNil(try secret("$(GITTICKETS_SHARED_SECRET)", .base64))
    }

    // MARK: - Empty and whitespace-only values

    func test_emptyStringReturnsNil() throws {
        XCTAssertNil(try secret("", .hex))
        XCTAssertNil(try secret("", .base64))
    }

    func test_whitespaceOnlyReturnsNil() throws {
        for value in ["   ", "\n", "\t", " \n\t "] {
            XCTAssertNil(try secret(value, .hex), "hex accepted whitespace-only \(value.debugDescription)")
            XCTAssertNil(try secret(value, .base64), "base64 accepted whitespace-only \(value.debugDescription)")
        }
    }

    /// `"0x"` trims to zero hex digits, which is an even count. It must not
    /// slip through as a 0-byte key.
    func test_barePrefixReturnsNil() throws {
        XCTAssertNil(try secret("0x", .hex))
        XCTAssertNil(try secret("0X\n", .hex))
    }

    /// Whitespace *inside* the payload must fail rather than decode to some
    /// other byte sequence.
    func test_internalWhitespaceReturnsNil() throws {
        XCTAssertNil(try secret("de ad be ef", .hex))
        XCTAssertNil(try secret("dead\nbeef", .hex))
        XCTAssertNil(try secret("3q2 +7w==", .base64))
    }

    // MARK: - Non-string plist values

    /// A number, bool, array, dict, or date is treated as absent. There is no
    /// coercion path that could invent a key from these.
    func test_nonStringPlistValuesReturnNil() throws {
        let values: [(String, Any)] = [
            ("integer", 42),
            ("double", 3.5),
            ("bool", true),
            ("array", ["dead", "beef"]),
            ("dictionary", ["value": "deadbeef"]),
            ("date", Date(timeIntervalSince1970: 0)),
            ("data", Data([0xde, 0xad, 0xbe, 0xef])),
        ]
        for (label, value) in values {
            XCTAssertNil(try secret(value, .hex), "hex coerced a \(label) plist value")
            XCTAssertNil(try secret(value, .base64), "base64 coerced a \(label) plist value")
        }
    }

    /// A one-element array of a valid hex string is the shape you get from a
    /// mis-typed plist entry. It must not be unwrapped.
    func test_singleElementArrayIsNotUnwrapped() throws {
        XCTAssertNil(try secret(["deadbeef"], .hex))
    }

    // MARK: - Default bundle

    /// The `bundle:` default is `.main`. Under `swift test` that is the test
    /// runner, which carries no such key — so this asserts the default
    /// argument resolves and returns a clean nil rather than trapping.
    func test_defaultBundleIsMainAndMissingKeyIsNil() {
        XCTAssertNil(SharedSecret(infoPlistKey: "GitTicketsSharedSecretDefinitelyAbsent", encoding: .hex))
    }

    // MARK: - Regression guards on the underlying decoders

    /// Before v2.1.0, `init?(hex:)` returned a non-nil 0-byte secret for these
    /// — a key that signs every request identically and fails only at the
    /// relay. Guarded here because the Info.plist path delegates to it.
    func test_hexDecoderRejectsZeroLengthInput() {
        XCTAssertNil(SharedSecret(hex: ""))
        XCTAssertNil(SharedSecret(hex: "   "))
        XCTAssertNil(SharedSecret(hex: "0x"))
        XCTAssertNil(SharedSecret(hex: "\n"))
    }

    func test_base64DecoderRejectsZeroLengthInput() {
        XCTAssertNil(SharedSecret(base64: ""))
        XCTAssertNil(SharedSecret(base64: "   "))
    }

    /// Found by the v2.1.0 adversarial audit. `UInt8(_:radix:)` accepts a
    /// leading `+`, so `"+1+1"` used to decode to the two bytes `01 01` — a
    /// well-formed key from a string that is not hex at all. The only symptom
    /// would have been `401 signatureMismatch` at the relay.
    func test_hexDecoderRejectsSignPrefixedDigits() throws {
        for value in ["+1", "+1+1", "+d+e", "0x+1+1", "-1-1", "  +1+1  "] {
            XCTAssertNil(SharedSecret(hex: value), "hex accepted \(value.debugDescription)")
            XCTAssertNil(try secret(value, .hex), "Info.plist hex accepted \(value.debugDescription)")
        }
    }

    /// `"0b11"` is legitimately four hex digits (`0b 11`) — the sign-prefix
    /// fix must not over-reject valid input that merely looks like a literal
    /// prefix from another base.
    func test_hexDecoderStillAcceptsDigitsResemblingOtherBasePrefixes() throws {
        XCTAssertEqual(try secret("0b11", .hex)?.bytes, Data([0x0b, 0x11]))
        XCTAssertEqual(try secret("0e0e", .hex)?.bytes, Data([0x0e, 0x0e]))
    }

    /// Found by the v2.1.0 adversarial audit. `Data(base64Encoded: "====")`
    /// returns a single `0x00` byte, which is non-empty and so passed the
    /// emptiness guard as a 1-byte all-zero key.
    func test_base64DecoderRejectsPaddingOnlyPayload() throws {
        for value in ["====", "========", "============", "    ====", "====\n"] {
            XCTAssertNil(SharedSecret(base64: value), "base64 accepted \(value.debugDescription)")
            XCTAssertNil(try secret(value, .base64), "Info.plist base64 accepted \(value.debugDescription)")
        }
    }

    /// Unicode look-alike digits must not decode. `"dead٧eef"` uses an
    /// Arabic-Indic seven.
    func test_hexDecoderRejectsUnicodeLookalikeDigits() throws {
        XCTAssertNil(try secret("dead\u{0667}eef", .hex))
        XCTAssertNil(try secret("\u{FF10}\u{FF11}", .hex))  // fullwidth 0 and 1
    }

    /// No successfully decoded secret is ever empty.
    func test_decodedSecretIsNeverEmpty() throws {
        let bundle = try makeBundle([key: "deadbeef"])
        for encoding in [SharedSecret.Encoding.hex, .base64] {
            let secret = try XCTUnwrap(
                SharedSecret(infoPlistKey: key, encoding: encoding, bundle: bundle),
                "\(encoding) should decode \"deadbeef\""
            )
            XCTAssertFalse(secret.bytes.isEmpty)
        }
    }
}
