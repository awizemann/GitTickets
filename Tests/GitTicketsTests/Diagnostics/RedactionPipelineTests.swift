import XCTest
@testable import GitTickets

final class RedactionPipelineTests: XCTestCase {

    func test_emailReplacementSingleAndMultiple() {
        let input = "Contact: a@b.com or admin@example.org for help."
        let output = RedactionPipeline.redact(input, with: [.email])
        XCTAssertEqual(output, "Contact: [email redacted] or [email redacted] for help.")
    }

    func test_emailReplacementHandlesPlusAndDots() {
        let input = "a.b+test@foo.example.com"
        let output = RedactionPipeline.redact(input, with: [.email])
        XCTAssertEqual(output, "[email redacted]")
    }

    func test_ipv4Replacement() {
        let input = "Connecting to 192.168.1.1 and 8.8.8.8 ..."
        let output = RedactionPipeline.redact(input, with: [.ipv4])
        XCTAssertEqual(output, "Connecting to [ip redacted] and [ip redacted] ...")
    }

    func test_ipv6Replacement() {
        let input = "Source 2001:db8::1 dropped"
        let output = RedactionPipeline.redact(input, with: [.ipv6])
        XCTAssertTrue(output.contains("[ip redacted]"))
        XCTAssertFalse(output.contains("2001:db8"))
    }

    func test_bearerTokenReplacement() {
        let input = "Authorization: Bearer abcdef1234567890ABCDEF"
        let output = RedactionPipeline.redact(input, with: [.bearerToken])
        XCTAssertEqual(output, "Authorization: Bearer [token redacted]")
    }

    func test_bearerTokenIgnoresShortStrings() {
        let input = "Bearer x"
        let output = RedactionPipeline.redact(input, with: [.bearerToken])
        XCTAssertEqual(output, "Bearer x", "regex requires 16+ chars to avoid false positives")
    }

    func test_orderedApplication() {
        // Sequential pipeline: email runs first, IPv4 second.
        let input = "Send 1.2.3.4 to admin@example.com"
        let output = RedactionPipeline.redact(input, with: [.email, .ipv4])
        XCTAssertEqual(output, "Send [ip redacted] to [email redacted]")
    }

    func test_emptyRedactorsLeavesTextUnchanged() {
        let input = "untouched 1.2.3.4 a@b.com"
        XCTAssertEqual(RedactionPipeline.redact(input, with: []), input)
    }

    func test_emptyInputProducesEmptyOutput() {
        XCTAssertEqual(RedactionPipeline.redact("", with: [.email, .ipv4]), "")
    }

    func test_customRedactor() {
        let pattern = try! NSRegularExpression(pattern: #"sk-[A-Z0-9]{16,}"#, options: .caseInsensitive)
        let custom = DiagnosticsRedactor(name: "openai", regex: pattern, replacement: "[openai key redacted]")
        let input = "API key: sk-abcdefghijklmnop"
        XCTAssertEqual(
            RedactionPipeline.redact(input, with: [custom]),
            "API key: [openai key redacted]"
        )
    }

    func test_realisticBlobWithEverything() {
        let input = """
        OS: iOS 17.5
        Free disk: 24.1 GB
        Recent logs:
          12:34:01 com.app.net warning: Request to 10.0.0.5 failed for user@example.com
          12:34:02 com.app.api error: Authorization: Bearer abcdef1234567890ABCDEF rejected
        """
        let output = RedactionPipeline.redact(input, with: [.bearerToken, .email, .ipv4, .ipv6])
        XCTAssertFalse(output.contains("user@example.com"))
        XCTAssertFalse(output.contains("10.0.0.5"))
        XCTAssertFalse(output.contains("abcdef1234567890ABCDEF"))
        XCTAssertTrue(output.contains("Free disk: 24.1 GB"))
    }

    // MARK: - Regression tests for code-review findings

    /// C5: IPv4 redactor used to match four-part version strings like
    /// `1.0.0.123` wrapped in parens (`App: MyApp 1.0.0 (1.0.0.123)`),
    /// stripping the build number that triage relies on. The new regex
    /// uses paren context exclusion to avoid this.
    func test_ipv4DoesNotMatchVersionStringInParens() {
        let input = "App: MyApp 1.0.0 (1.0.0.123)"
        let output = RedactionPipeline.redact(input, with: [.ipv4])
        XCTAssertEqual(output, input)
    }

    /// C5: IPv4 still must match real addresses surrounded by typical log
    /// context (whitespace, commas, end of line).
    func test_ipv4StillMatchesRealAddresses() {
        let output = RedactionPipeline.redact("from 192.168.1.42 at 10.0.0.5,", with: [.ipv4])
        XCTAssertEqual(output, "from [ip redacted] at [ip redacted],")
    }

    /// C6: IPv6 redactor used to match HH:MM:SS clock timestamps because
    /// decimal digits are a subset of hex. New regex requires at least one
    /// A-F letter inside the match.
    func test_ipv6DoesNotMatchClockTimestamps() {
        let input = "  09:30:45 com.app warning: Something happened"
        let output = RedactionPipeline.redact(input, with: [.ipv6])
        XCTAssertEqual(output, input)
        XCTAssertTrue(output.contains("09:30:45"))
    }

    /// C6: IPv6 still must match real addresses, including loopback `::1`
    /// (the old `\b` boundary failed to match leading-`:` addresses).
    func test_ipv6MatchesLoopbackAndStandardForms() {
        XCTAssertTrue(RedactionPipeline.redact("from 2001:db8::1 ", with: [.ipv6]).contains("[ip redacted]"))
        XCTAssertTrue(RedactionPipeline.redact("from ::1 ", with: [.ipv6]).contains("[ip redacted]"))
    }

    /// C7: When bearer runs AFTER ipv4/ipv6, an embedded IP-shaped
    /// substring inside the token gets rewritten to `[ip redacted]`,
    /// breaking the bearer charset and leaking the rest of the token.
    /// The default redactor order now runs bearer first.
    func test_defaultRedactorOrderProtectsBearerWithEmbeddedIPv4() {
        let input = "Authorization: Bearer eyJhbGciOi.10.0.0.1.JzdWIiOiIxMjM0NTY3ODkw"
        let output = RedactionPipeline.redact(input, with: DiagnosticsPolicy.default.redactors)
        XCTAssertTrue(output.contains("[token redacted]"))
        XCTAssertFalse(output.contains("eyJhbGciOi"))
        XCTAssertFalse(output.contains("JzdWIiOiIxMjM0NTY3ODkw"))
    }

    // MARK: - absolutePath

    /// A realistic macOS diagnostics blob from a privacy-sensitive document
    /// app filing to a PUBLIC repo. The abstract-regex version of this test
    /// is what missed the earlier over-match bugs, so this asserts on the
    /// real blob shape: version strings, clock timestamps, subsystem names,
    /// log prose, and paths mixed together.
    func test_realisticBlobRedactsPathsButKeepsTriageFields() {
        let input = """
        OS: macOS Version 15.5 (Build 24F74)
        App: ShabuBox 2.1.0 (2.1.0.4821)
        Device: MacBookPro18,3
        Locale: en_US
        Free disk: 24.1 GB
        Memory (physical): 32 GB

        Recent logs (300s):
          12:34:01 com.shabubox.app.vault error: open failed for \
        /Users/alan/Library/Containers/com.shabubox.app/Data/Documents/SomeTaxReturn2024.pdf (errno 2)
          12:34:02 com.shabubox.app.vault info: falling back to ~/Library/Caches/com.shabubox.app/index.sqlite
          12:34:03 com.shabubox.app.sync info: staged /private/var/folders/x9/qz7/T/upload-4821.tmp
          12:34:04 com.shabubox.app.sync debug: framework /System/Library/Frameworks/Foundation.framework loaded
          12:34:05 com.shabubox.app.net info: GET https://cdn.example.com/library/manifest.json -> 200
        """
        let output = RedactionPipeline.redact(input, with: DiagnosticsPolicy.default.redactors)

        // 1. The sensitive path is gone in full: account name AND document name.
        XCTAssertFalse(output.contains("SomeTaxReturn2024.pdf"), "filename stranded — the exact bug being fixed")
        XCTAssertFalse(output.contains("alan"), "account short name leaked")
        XCTAssertFalse(output.contains("/Users/"))
        XCTAssertFalse(output.contains("Containers"))
        XCTAssertFalse(output.contains("~/Library"))
        XCTAssertFalse(output.contains("index.sqlite"))
        XCTAssertFalse(output.contains("upload-4821.tmp"))
        XCTAssertFalse(output.contains("/private/var"))

        // 2. Triage fields survive untouched.
        XCTAssertTrue(output.contains("OS: macOS Version 15.5 (Build 24F74)"), "macOS version")
        XCTAssertTrue(output.contains("App: ShabuBox 2.1.0 (2.1.0.4821)"), "app version + build")
        XCTAssertTrue(output.contains("Device: MacBookPro18,3"), "hardware model")
        XCTAssertTrue(output.contains("Locale: en_US"), "locale")
        XCTAssertTrue(output.contains("Free disk: 24.1 GB"))
        XCTAssertTrue(output.contains("12:34:01"), "clock timestamps")
        XCTAssertTrue(output.contains("com.shabubox.app.vault"), "subsystem names")
        XCTAssertTrue(output.contains("(errno 2)"), "error context")
        XCTAssertTrue(output.contains("-> 200"), "status code")

        // 3. System framework paths stay readable — no user identity in them.
        XCTAssertTrue(
            output.contains("/System/Library/Frameworks/Foundation.framework"),
            "system paths carry no PII and are worth keeping for triage"
        )

        // 4. The URL is not partly redacted despite containing /library/.
        XCTAssertTrue(output.contains("https://cdn.example.com/library/manifest.json"))
    }

    func test_absolutePathCoversAllDocumentedPrefixes() {
        let prefixes = [
            "/Users/alan/x.pdf",
            "~/Documents/x.pdf",
            "/Volumes/Backup/x.pdf",
            "/private/var/folders/zz/T/x.tmp",
            "/var/log/shabubox.log",
            "/tmp/staging-1.png",
            "/Applications/ShabuBox.app/Contents/MacOS/ShabuBox",
            "/Library/Preferences/com.shabubox.plist",
        ]
        for path in prefixes {
            XCTAssertEqual(
                RedactionPipeline.redact("opened \(path) ok", with: [.absolutePath]),
                "opened [path redacted] ok",
                "prefix not fully covered: \(path)"
            )
        }
    }

    /// The whole point: the trailing filename must go with the path. A
    /// redactor that stops at the last separator leaks the document name.
    func test_absolutePathConsumesTrailingFilename() {
        let output = RedactionPipeline.redact(
            "/Users/alan/Library/Containers/com.shabubox.app/Data/Documents/SomeTaxReturn2024.pdf",
            with: [.absolutePath]
        )
        XCTAssertEqual(output, "[path redacted]")
    }

    // MARK: - absolutePath over-match guards

    /// The leading boundary must reject a preceding host/path character, or a
    /// URL whose path happens to contain a redactable-looking segment gets
    /// mangled and the report becomes unreadable.
    func test_absolutePathDoesNotCorruptURLs() {
        let urls = [
            "https://example.com/library/foo",
            "https://cdn.example.com/var/x",
            "https://api.github.com/repos/o/r/issues/12",
            "https://example.com/Users/profile",
            "https://example.com/private/docs",
            "https://downloads.example.com/Applications/tool.zip",
        ]
        for url in urls {
            XCTAssertEqual(
                RedactionPipeline.redact("fetching \(url) now", with: [.absolutePath]),
                "fetching \(url) now",
                "URL corrupted: \(url)"
            )
        }
    }

    /// `~` requires a following `/`. A bare tilde in prose, or `~=`, is not a
    /// path.
    func test_absolutePathRequiresSlashAfterTilde() {
        let inputs = [
            "threshold ~= 0.5 tolerance",
            "roughly ~ 30 seconds",
            "range 5~10 items",
            "backup file report~ kept",
        ]
        for input in inputs {
            XCTAssertEqual(
                RedactionPipeline.redact(input, with: [.absolutePath]),
                input,
                "bare tilde matched: \(input)"
            )
        }
    }

    /// System prefixes are deliberately out of scope: they hold no user
    /// identity and keeping them intact preserves triage value. Note
    /// `/System/Library/` is protected by the boundary rule, not by an
    /// exception.
    func test_absolutePathLeavesSystemPathsAlone() {
        let systemPaths = [
            "/System/Library/Frameworks/Foundation.framework/Foundation",
            "/usr/lib/swift/libswiftCore.dylib",
            "/opt/homebrew/var/log/x",
            "/bin/sh",
            "/etc/hosts",
        ]
        for path in systemPaths {
            XCTAssertEqual(
                RedactionPipeline.redact("loaded \(path) ok", with: [.absolutePath]),
                "loaded \(path) ok",
                "system path redacted: \(path)"
            )
        }
    }

    /// Trailing punctuation belongs to the sentence, not the path. Swallowing
    /// it corrupts source locations and lists.
    func test_absolutePathDoesNotSwallowTrailingPunctuation() {
        XCTAssertEqual(
            RedactionPipeline.redact("opened /Users/alan/x.pdf.", with: [.absolutePath]),
            "opened [path redacted]."
        )
        XCTAssertEqual(
            RedactionPipeline.redact("both /Users/alan/a.pdf, /tmp/b.pdf.", with: [.absolutePath]),
            "both [path redacted], [path redacted]."
        )
        XCTAssertEqual(
            RedactionPipeline.redact("crash at /Users/alan/src/Main.swift:42:17", with: [.absolutePath]),
            "crash at [path redacted]:42:17",
            "line:column must survive for triage"
        )
        XCTAssertEqual(
            RedactionPipeline.redact("missing (\"/Users/alan/x.pdf\") here", with: [.absolutePath]),
            "missing (\"[path redacted]\") here"
        )
    }

    /// Version strings, build numbers and clock timestamps must not be
    /// affected — the same fields the earlier IPv4/IPv6 over-match bugs ate.
    func test_absolutePathLeavesVersionAndTimestampFieldsAlone() {
        let inputs = [
            "App: MyApp 1.0.0 (1.0.0.123)",
            "macOS Version 15.5 (Build 24F74)",
            "  09:30:45 com.app warning: something happened",
            "Device: MacBookPro18,3",
            "Locale: en_US",
            "Free disk: 24.1 GB",
        ]
        for input in inputs {
            XCTAssertEqual(RedactionPipeline.redact(input, with: [.absolutePath]), input)
        }
    }

    /// Case-insensitivity is inherited from the shared regex options and is
    /// deliberate: Apple filesystems are case-insensitive, so `/users/` is
    /// the same file and the same leak.
    func test_absolutePathIsCaseInsensitiveByDesign() {
        XCTAssertEqual(
            RedactionPipeline.redact("/users/alan/taxes.pdf", with: [.absolutePath]),
            "[path redacted]"
        )
        XCTAssertEqual(
            RedactionPipeline.redact("/VAR/log/x", with: [.absolutePath]),
            "[path redacted]"
        )
    }

    /// Non-ASCII filenames must be consumed too. APFS stores names
    /// decomposed, so this also exercises the combining-mark class — without
    /// it the match would stop mid-filename and publish the document name.
    func test_absolutePathConsumesNonASCIIFilenames() {
        for name in ["Café-Réçu.pdf", "確定申告2024.pdf", "Ünïcode.pdf", "receipt-📄.pdf"] {
            XCTAssertEqual(
                RedactionPipeline.redact("/Users/alan/Documents/\(name)", with: [.absolutePath]),
                "[path redacted]",
                "non-ASCII filename stranded: \(name)"
            )
        }
    }

    /// `file://` URLs are real paths and must redact, even though the path is
    /// preceded by `/`. Percent-encoding also means space-bearing filenames
    /// are fully covered in this form.
    func test_absolutePathRedactsFileURLs() {
        XCTAssertEqual(
            RedactionPipeline.redact("file:///Users/alan/Documents/Passport.pdf", with: [.absolutePath]),
            "file://[path redacted]"
        )
        XCTAssertEqual(
            RedactionPipeline.redact("file:///Users/alan/Tax%20Return%202024.pdf", with: [.absolutePath]),
            "file://[path redacted]",
            "percent-encoded spaces are covered"
        )
    }

    /// Documents the known limitation honestly rather than pretending the
    /// regex is exact: a space ends the match, so a multi-word filename is
    /// only partly removed. The identifying half (account name) always goes.
    /// If this behaviour ever changes, this test should be updated
    /// deliberately, not silently.
    func test_absolutePathTruncatesAtSpace_knownLimitation() {
        let output = RedactionPipeline.redact(
            "/Users/alan/Documents/Tax Return 2024.pdf",
            with: [.absolutePath]
        )
        XCTAssertEqual(output, "[path redacted] Return 2024.pdf")
        XCTAssertFalse(output.contains("alan"), "the identifying half is always removed")
    }

    /// Known gap, pinned so it is visible rather than folklore: separators
    /// that are backslash-escaped (JSON escaping solidus) are not recognised
    /// and the path is not redacted at all.
    func test_absolutePathMissesEscapedSeparators_knownLimitation() {
        let input = #"{"path":"\/Users\/alan\/Taxes.pdf"}"#
        XCTAssertEqual(
            RedactionPipeline.redact(input, with: DiagnosticsRedactor.recommended),
            input,
            "escaped-solidus JSON is a documented gap; if this starts redacting, update the docs too"
        )
    }

    /// Real Apple-platform path shapes that must be covered: iOS data
    /// containers, simulator devices, and `NSError` userInfo keys.
    func test_absolutePathCoversApplePlatformContainerPaths() {
        let paths = [
            "/var/mobile/Containers/Data/Application/1A2B-3C4D/Documents/Taxes.pdf",
            "/private/var/mobile/Library/Caches/vault.db",
            "/Users/alan/Library/Developer/CoreSimulator/Devices/ABC/data/Taxes.pdf",
        ]
        for path in paths {
            XCTAssertEqual(
                RedactionPipeline.redact(path, with: [.absolutePath]),
                "[path redacted]",
                "container path not fully redacted: \(path)"
            )
        }
        XCTAssertEqual(
            RedactionPipeline.redact("NSFilePath=/Users/alan/Documents/Taxes.pdf", with: [.absolutePath]),
            "NSFilePath=[path redacted]"
        )
    }

    /// A colon-separated `PATH` must lose only the user-owned entry; the
    /// system entries stay readable.
    func test_absolutePathRedactsOnlyUserEntriesInSearchPath() {
        XCTAssertEqual(
            RedactionPipeline.redact("PATH=/Users/alan/bin:/usr/bin:/bin", with: [.absolutePath]),
            "PATH=[path redacted]:/usr/bin:/bin"
        )
    }

    /// Quoted and bracketed paths are common in shell echoes and log prose;
    /// the delimiters must survive so the line stays parseable.
    func test_absolutePathPreservesSurroundingDelimiters() {
        XCTAssertEqual(
            RedactionPipeline.redact("cp '/Users/alan/Taxes.pdf' /tmp/out.pdf", with: [.absolutePath]),
            "cp '[path redacted]' [path redacted]"
        )
        XCTAssertEqual(
            RedactionPipeline.redact("[/Users/alan/x.pdf] {/tmp/y.pdf}", with: [.absolutePath]),
            "[[path redacted]] {[path redacted]}"
        )
    }

    /// An IP or email that sits inside a filename must not survive as a
    /// fragment once the whole path is consumed.
    func test_absolutePathConsumesAddressesInsideFilenames() {
        XCTAssertEqual(
            RedactionPipeline.redact("/Users/alan/10.0.0.5.log", with: DiagnosticsRedactor.recommended),
            "[path redacted]"
        )
        XCTAssertEqual(
            RedactionPipeline.redact("/Users/alan/alan@example.com.vcf", with: DiagnosticsRedactor.recommended),
            "[path redacted]"
        )
    }

    // MARK: - Ordering regressions

    /// Mirrors `test_defaultRedactorOrderProtectsBearerWithEmbeddedIPv4` for
    /// paths. `[ip redacted]` contains `[`, space and `]`, none of which are
    /// path characters — so if ipv4 runs first it splits the path, the path
    /// match stops at the bracket, and the FILENAME survives into a public
    /// issue. This is the interaction the ShabuBox adopter hit.
    func test_defaultRedactorOrderProtectsPathWithEmbeddedIPv4() {
        let input = "open failed: /Users/alan/Library/Logs/10.0.0.5/SomeTaxReturn2024.pdf"

        let output = RedactionPipeline.redact(input, with: DiagnosticsPolicy.default.redactors)
        XCTAssertEqual(output, "open failed: [path redacted]")
        XCTAssertFalse(output.contains("SomeTaxReturn2024.pdf"))
        XCTAssertFalse(output.contains("alan"))

        // Negative control: prove the wrong order really does strand the
        // filename, so this test cannot pass vacuously.
        let wrongOrder = RedactionPipeline.redact(input, with: [.ipv4, .absolutePath])
        XCTAssertTrue(
            wrongOrder.contains("SomeTaxReturn2024.pdf"),
            "expected the bad order to strand the filename; if it no longer does, this guard is obsolete"
        )
    }

    /// Same hazard via `.email` — `[email redacted]` inserts the same
    /// bracket/space characters, which is why `.absolutePath` precedes email
    /// as well as the IP redactors.
    func test_defaultRedactorOrderProtectsPathWithEmbeddedEmail() {
        let input = "open failed: /Users/alan/Mail/alan@example.com/SomeTaxReturn2024.pdf"

        let output = RedactionPipeline.redact(input, with: DiagnosticsPolicy.default.redactors)
        XCTAssertEqual(output, "open failed: [path redacted]")
        XCTAssertFalse(output.contains("SomeTaxReturn2024.pdf"))
        XCTAssertFalse(output.contains("example.com"))

        let wrongOrder = RedactionPipeline.redact(input, with: [.email, .absolutePath])
        XCTAssertTrue(
            wrongOrder.contains("SomeTaxReturn2024.pdf"),
            "expected the bad order to strand the filename"
        )
    }

    /// Adding a path redactor must not regress the bearer-first guarantee:
    /// bearer still runs before everything that could corrupt its charset.
    func test_recommendedOrderStillProtectsBearerTokens() {
        let input = "Authorization: Bearer eyJhbGciOi.10.0.0.1.JzdWIiOiIxMjM0NTY3ODkw"
        let output = RedactionPipeline.redact(input, with: DiagnosticsRedactor.recommended)
        XCTAssertTrue(output.contains("[token redacted]"))
        XCTAssertFalse(output.contains("eyJhbGciOi"))
        XCTAssertFalse(output.contains("JzdWIiOiIxMjM0NTY3ODkw"))
    }

    // MARK: - recommended / policy default

    func test_recommendedOrderIsExactAndDocumented() {
        XCTAssertEqual(
            DiagnosticsRedactor.recommended.map(\.name),
            ["bearerToken", "absolutePath", "email", "ipv4", "ipv6"]
        )
    }

    func test_policyDefaultUsesRecommendedPipeline() {
        XCTAssertEqual(
            DiagnosticsPolicy.default.redactors.map(\.name),
            DiagnosticsRedactor.recommended.map(\.name)
        )
        XCTAssertEqual(
            DiagnosticsPolicy().redactors.map(\.name),
            DiagnosticsRedactor.recommended.map(\.name),
            "the memberwise init default must match the .default policy"
        )
    }

    /// A caller-supplied array is used verbatim — the pipeline must not
    /// "helpfully" reorder it. Adopters may deliberately depend on position.
    func test_pipelineDoesNotReorderCallerSuppliedRedactors() {
        let input = "/Users/alan/Library/Logs/10.0.0.5/SomeTaxReturn2024.pdf"
        let deliberatelyBad = RedactionPipeline.redact(input, with: [.ipv4, .absolutePath])
        XCTAssertTrue(
            deliberatelyBad.contains("SomeTaxReturn2024.pdf"),
            "caller order must be honoured verbatim, even when it is a bad order"
        )
    }

    /// Appending a custom redactor to `recommended` is the documented
    /// extension path; it must keep working end to end.
    func test_recommendedComposesWithCustomRedactor() {
        let pattern = try! NSRegularExpression(pattern: #"sk-[A-Z0-9]{16,}"#, options: .caseInsensitive)
        let custom = DiagnosticsRedactor(name: "openai", regex: pattern, replacement: "[openai key redacted]")
        let output = RedactionPipeline.redact(
            "key sk-abcdefghijklmnop for /Users/alan/Documents/Taxes.pdf",
            with: DiagnosticsRedactor.recommended + [custom]
        )
        XCTAssertEqual(output, "key [openai key redacted] for [path redacted]")
    }
}
