import CoreGraphics
import ImageIO
import SwiftUI
import XCTest
@testable import GitTickets

/// Covers the full-size preview for a *pending* (not-yet-submitted) attachment
/// in the compose form.
///
/// The decoder is deliberately a pure function over `Data`, so the interesting
/// behavior — undecodable bytes, oversized images — is testable on both
/// platforms without a view hierarchy or a snapshot baseline.
@MainActor
final class AttachmentPreviewSheetTests: XCTestCase {

    /// Smallest valid 1×1 PNG, matching the fixture already used by
    /// `GitTicketsViewTests`.
    private let onePixelPNGBase64 =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="

    // MARK: - AttachmentImageDecoder

    func test_decodeReturnsNilForEmptyData() {
        XCTAssertNil(AttachmentImageDecoder.decode(Data()))
    }

    func test_decodeReturnsNilForGarbageBytes() {
        // The "corrupt / undecodable attachment" path. Must be nil rather than
        // a crash so the sheet can show its "No preview available" state.
        XCTAssertNil(AttachmentImageDecoder.decode(Data([0x00, 0x01, 0x02, 0x03, 0x04])))
    }

    func test_decodeReturnsNilForNonImageBytes() {
        // A PDF header is a realistic non-image attachment: recognisable as a
        // file, not decodable as a bitmap by CGImageSource.
        let pdf = Data("%PDF-1.7\n%%EOF\n".utf8)
        XCTAssertNil(AttachmentImageDecoder.decode(pdf))
    }

    func test_decodeDecodesSmallPNGAtItsNativeSize() throws {
        let data = try XCTUnwrap(Data(base64Encoded: onePixelPNGBase64))
        let image = try XCTUnwrap(AttachmentImageDecoder.decode(data))
        // Never upscaled to the ceiling.
        XCTAssertEqual(image.width, 1)
        XCTAssertEqual(image.height, 1)
    }

    func test_decodeDownsamplesOversizedImageToTheCeiling() throws {
        // Guards the "very large image" case: an attachment must not be decoded
        // at full resolution just to be looked at.
        let data = try makePNG(width: 900, height: 300)
        let image = try XCTUnwrap(AttachmentImageDecoder.decode(data, maxPixelSize: 128))
        XCTAssertEqual(max(image.width, image.height), 128)
        // Aspect ratio preserved (900:300 == 3:1), allowing for rounding.
        XCTAssertTrue((41...44).contains(image.height), "height was \(image.height)")
    }

    func test_decodeLeavesUndersizedImageUntouchedByTheCeiling() throws {
        let data = try makePNG(width: 64, height: 48)
        let image = try XCTUnwrap(AttachmentImageDecoder.decode(data, maxPixelSize: 2048))
        XCTAssertEqual(image.width, 64)
        XCTAssertEqual(image.height, 48)
    }

    func test_defaultCeilingIsBounded() {
        // A regression guard: an unbounded (or absurd) ceiling would defeat the
        // whole point of routing through CGImageSource thumbnails.
        XCTAssertGreaterThan(AttachmentImageDecoder.defaultMaxPixelSize, 1024)
        XCTAssertLessThanOrEqual(AttachmentImageDecoder.defaultMaxPixelSize, 4096)
    }

    // MARK: - Footer meta line

    func test_metaLineIncludesDimensionsSizeAndType() {
        let line = AttachmentPreviewSheet.metaLine(
            byteCount: 4096,
            mimeType: "image/png",
            pixelSize: (1024, 768)
        )
        XCTAssertTrue(line.hasPrefix("1024 × 768 · "), line)
        XCTAssertTrue(line.hasSuffix(" · image/png"), line)
        XCTAssertTrue(line.contains(AttachmentPreviewSheet.formattedByteCount(4096)), line)
    }

    func test_metaLineOmitsDimensionsWhenNotAnImage() {
        let line = AttachmentPreviewSheet.metaLine(
            byteCount: 2048,
            mimeType: "application/pdf",
            pixelSize: nil
        )
        XCTAssertFalse(line.contains("×"), line)
        XCTAssertTrue(line.hasSuffix("application/pdf"), line)
    }

    func test_metaLineOmitsEmptyMimeType() {
        let line = AttachmentPreviewSheet.metaLine(byteCount: 10, mimeType: "", pixelSize: nil)
        XCTAssertFalse(line.hasSuffix("·"), line)
        XCTAssertEqual(line, AttachmentPreviewSheet.formattedByteCount(10))
    }

    // MARK: - PendingAttachment identity

    func test_eachPresentationGetsAFreshIdentity() {
        // `.sheet(item:)` keys off `id`; a stable id would let SwiftUI reuse the
        // previous sheet's decoded state when the user re-opens the same file.
        let bytes = Data([0x01, 0x02])
        let first = PendingAttachment(filename: "a.png", mimeType: "image/png", data: bytes)
        let second = PendingAttachment(filename: "a.png", mimeType: "image/png", data: bytes)
        XCTAssertNotEqual(first.id, second.id)
    }

    func test_pendingAttachmentCarriesItsOwnBytes() {
        // Value semantics are what make removing the underlying attachment while
        // the preview is open harmless — there is no index and no shared buffer.
        var source = Data([0xAA, 0xBB])
        let pending = PendingAttachment(filename: "a.png", mimeType: "image/png", data: source)
        source.removeAll()
        XCTAssertEqual(pending.data, Data([0xAA, 0xBB]))
    }

    // MARK: - View construction

    func test_sheetBodyBuildsForDecodableImage() throws {
        let data = try XCTUnwrap(Data(base64Encoded: onePixelPNGBase64))
        let sheet = AttachmentPreviewSheet(
            attachment: PendingAttachment(filename: "shot.png", mimeType: "image/png", data: data),
            theme: .default
        )
        _ = sheet.body
    }

    func test_sheetBodyBuildsForUndecodableAttachment() {
        let sheet = AttachmentPreviewSheet(
            attachment: PendingAttachment(
                filename: "report.pdf",
                mimeType: "application/pdf",
                data: Data("%PDF-1.7".utf8)
            ),
            theme: .default
        )
        _ = sheet.body
    }

    func test_sheetBodyBuildsUnderACustomTheme() {
        // The preview must paint from the theme, not a hardcoded palette.
        let theme = GitTicketsTheme(accentColor: .pink, cornerRadius: 22)
        let sheet = AttachmentPreviewSheet(
            attachment: PendingAttachment(filename: "a.png", mimeType: "image/png", data: Data()),
            theme: theme
        )
        _ = sheet.body
    }

    // MARK: - Cell affordance

    func test_thumbnailStillBuildsWithoutAnExpandAction() {
        // The expand affordance is additive: omitting it must leave the pre-2.1
        // cell intact (no badge, no extra accessibility element).
        let cell = ScreenshotThumbnail(filename: "a.png", data: Data(), onRemove: {})
        XCTAssertNil(cell.onExpand)
        _ = cell.body
    }

    func test_thumbnailBuildsWithAnExpandAction() throws {
        var expanded = false
        let data = try XCTUnwrap(Data(base64Encoded: onePixelPNGBase64))
        let cell = ScreenshotThumbnail(
            filename: "a.png",
            data: data,
            onRemove: {},
            onExpand: { expanded = true }
        )
        _ = cell.body
        // Not a dead control: the closure is the one the form supplied.
        try XCTUnwrap(cell.onExpand)()
        XCTAssertTrue(expanded)
    }

    // MARK: - Helpers

    /// Encodes a solid-color PNG of the requested pixel size, so the
    /// downsampling tests don't need a binary fixture in the repo.
    private func makePNG(width: Int, height: Int) throws -> Data {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let image = try XCTUnwrap(context.makeImage())
        let buffer = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(buffer, "public.png" as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return buffer as Data
    }
}
