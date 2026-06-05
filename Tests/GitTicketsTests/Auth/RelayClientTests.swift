import XCTest
@testable import GitTickets

/// Tests covering ``RelayClient`` regressions surfaced by the PR 1–8
/// code review. Submission-level integration is covered by
/// ``RelaySubmitterTests``.
final class RelayClientTests: XCTestCase {

    // MARK: - Multipart sanitization (C13)

    func test_multipartSanitizesFilenameQuotes() throws {
        let bytes = Data("payload".utf8)
        let attachment = ReportAttachment(
            filename: "bad\"name; filename=\"injected.png",
            mimeType: "image/png",
            data: bytes
        )
        let body = try RelayClient.encodeMultipart(attachment: attachment, boundary: "B")
        let bodyString = String(data: body, encoding: .utf8) ?? ""
        XCTAssertFalse(bodyString.contains("filename=\"bad\"name"), "embedded quote must be stripped")
        XCTAssertFalse(bodyString.contains("name=\"injected.png\""), "stripping must close the injection vector")
    }

    func test_multipartStripsCRLFFromFilename() throws {
        let attachment = ReportAttachment(
            filename: "evil\r\nX-Forwarded-Auth: admin\r\nfile.png",
            mimeType: "image/png",
            data: Data()
        )
        let body = try RelayClient.encodeMultipart(attachment: attachment, boundary: "B")
        let bodyString = String(data: body, encoding: .utf8) ?? ""
        // The injected CRLF must not survive sanitization; the substring text
        // is left in-place (the filename can be ugly — what matters is that
        // the bytes can't escape the quoted-string into a forged header).
        XCTAssertFalse(bodyString.contains("evil\r\n"), "raw CR/LF must be stripped from filename")
        XCTAssertFalse(bodyString.contains("admin\r\nfile.png"))
        // Filename remains as a single (cleaned) quoted-string value.
        // `:` is also replaced with `_` to keep the value path-safe.
        XCTAssertTrue(bodyString.contains("filename=\"evilX-Forwarded-Auth_ adminfile.png\""))
    }

    func test_multipartRejectsUnsupportedMimeType() {
        let attachment = ReportAttachment(
            filename: "shell.sh",
            mimeType: "application/x-shellscript",
            data: Data()
        )
        XCTAssertThrowsError(try RelayClient.encodeMultipart(attachment: attachment, boundary: "B")) { error in
            guard case GitTicketsError.payloadInvalid = error else {
                XCTFail("Expected payloadInvalid for unsupported MIME, got \(error)")
                return
            }
        }
    }

    func test_multipartRejectsMimeTypeWithCRLF() {
        let attachment = ReportAttachment(
            filename: "ok.png",
            mimeType: "image/png\r\nX-Injected: 1",
            data: Data()
        )
        XCTAssertThrowsError(try RelayClient.encodeMultipart(attachment: attachment, boundary: "B"))
    }

    func test_multipartAllowsClassicImageTypes() throws {
        for mime in ["image/png", "image/jpeg", "image/gif", "image/webp"] {
            let attachment = ReportAttachment(filename: "ok", mimeType: mime, data: Data("x".utf8))
            XCTAssertNoThrow(try RelayClient.encodeMultipart(attachment: attachment, boundary: "B"),
                             "expected \(mime) to be allowed")
        }
    }

    func test_sanitizeFilenameFallsBackForEmptyResult() {
        XCTAssertEqual(RelayClient.sanitizeFilename(""), "attachment")
        XCTAssertEqual(RelayClient.sanitizeFilename("\"\""), "attachment")
    }
}
