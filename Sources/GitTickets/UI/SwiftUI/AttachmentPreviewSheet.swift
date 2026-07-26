//
//  AttachmentPreviewSheet.swift
//  GitTickets — full-size preview for a PENDING (not-yet-submitted) attachment.
//
//  Submitting a report is irreversible and, for a public repo, world-readable.
//  A 48pt thumbnail is not enough to confirm what a document screenshot
//  actually contains, so the compose form lets the user open any *pending*
//  attachment at full size and check it before pressing Submit. Deliberately
//  scoped to the compose form — the detail / My Reports thumbnails show
//  already-published bytes and are a separate surface.
//
//  Decoding goes through ImageIO rather than `NSImage`/`UIImage` for two
//  reasons: it keeps AppKit-only types out of shared iOS+macOS code, and
//  `CGImageSourceCreateThumbnailAtIndex` lets us cap the decoded pixel size so
//  a 5 MB / 10000px attachment can't balloon into a multi-hundred-megabyte
//  bitmap just to be looked at.
//
//  Follows the design tier (`design/design_handoff_gittickets_views_generic`):
//  native semantic surfaces via `GTSurface`, radii from
//  `GitTicketsTheme.cornerRadius` (card = +1, 52pt state tile like
//  `IssueStateCard`), 4pt spacing grid, native text styles so Dynamic Type
//  works, monospaced caption for numeric meta. No invented palette and — for a
//  viewer whose whole job is showing the user's own pixels honestly — no accent
//  tinting either: every color here is a system semantic one.
//
//  macOS 14+ / iOS 18+. SwiftUI only.
//

import CoreGraphics
import ImageIO
import SwiftUI

// MARK: - The thing being previewed

/// A pending attachment the user asked to inspect at full size.
///
/// Carries its **own copy of the bytes** rather than an index into the form's
/// `attachments` array. That is deliberate: the preview can never be
/// invalidated, blanked, or crashed by the underlying attachment being removed
/// while the sheet is up, and there is no index to go out of bounds.
///
/// Deliberately *not* `Hashable`: `.sheet(item:)` only needs `id`, and a
/// synthesized hash would walk up to 5 MB of `data` every time something hashed
/// one.
struct PendingAttachment: Identifiable {

    /// Fresh per presentation, so re-opening the same file presents a new sheet
    /// (and re-decodes) instead of reusing stale state.
    let id = UUID()

    let filename: String
    let mimeType: String
    let data: Data
}

// MARK: - Bounded, platform-neutral decoding

/// Decodes attachment bytes into a `CGImage` with a hard ceiling on pixel size.
///
/// Pure and synchronous so it can be unit-tested on both platforms without a
/// view hierarchy.
enum AttachmentImageDecoder {

    /// Longest-edge ceiling, in pixels, for a preview decode. Comfortably above
    /// any display we render into, far below what a 5 MB source image can be.
    static let defaultMaxPixelSize = 2048

    /// Returns a downsampled image for `data`, or `nil` when the platform's
    /// decoders don't recognise the bytes (a PDF, a corrupt PNG, garbage).
    static func decode(
        _ data: Data,
        maxPixelSize: Int = AttachmentImageDecoder.defaultMaxPixelSize
    ) -> CGImage? {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0
        else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // Applies the EXIF orientation so a phone screenshot isn't sideways.
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

// MARK: - The sheet

/// Shows one pending attachment at full size with an unambiguous way out.
struct AttachmentPreviewSheet: View {

    let attachment: PendingAttachment
    let theme: GitTicketsTheme

    @Environment(\.dismiss) private var dismiss

    /// Keeps "still working" and "definitively not an image" distinct, so the
    /// sheet never shows a permanent spinner and never claims failure
    /// prematurely.
    private enum Phase {
        case decoding
        case image(CGImage)
        case noPreview
    }

    /// Decoded once per presentation and cached, rather than re-decoded on every
    /// `body` evaluation.
    @State private var phase: Phase = .decoding

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider().overlay(GTSurface.hairline)
                footer
            }
            .background(GTSurface.ground)
            .navigationTitle("Attachment preview")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .task(id: attachment.id) {
            phase = AttachmentImageDecoder.decode(attachment.data).map(Phase.image) ?? .noPreview
        }
        #if os(macOS)
        // macOS sheets take their size from their content; without this the
        // sheet collapses to the intrinsic size of the footer.
        .frame(minWidth: 420, idealWidth: 680, minHeight: 360, idealHeight: 560)
        #endif
    }

    // MARK: Content states

    @ViewBuilder private var content: some View {
        switch phase {
        case .decoding:
            ProgressView()
                .controlSize(.large)
                .accessibilityLabel("Preparing preview")
        case .image(let image):
            Image(image, scale: 1, label: Text(imageLabel(for: image)))
                .resizable()
                .scaledToFit()
                .padding(16)
        case .noPreview:
            noPreviewCard
        }
    }

    /// Shown for anything the platform can't render — a PDF, a mislabelled
    /// file, truncated or corrupt image bytes. The expand control still opens
    /// this sheet rather than doing nothing, and the copy is explicit that the
    /// file is nonetheless going to be uploaded, which is the fact the user
    /// actually needs before submitting.
    private var noPreviewCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 52, height: 52)
                .background(
                    RoundedRectangle(cornerRadius: theme.cornerRadius + 1, style: .continuous)
                        .fill(GTSurface.subtleFill)
                )
                .accessibilityHidden(true)

            Text("No preview available").font(.headline)

            Text("This file isn't an image your device can display, so there's nothing to show at full size. It will still be attached to your report exactly as it is now.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
    }

    // MARK: Footer

    /// Identifies the file *and* carries the way out.
    ///
    /// Done deliberately lives here rather than in a `.toolbar`: this is
    /// ordinary content, so it is guaranteed to render on both platforms and the
    /// user can't be stranded in the modal by any sheet/toolbar quirk. It also
    /// matches the design tier's pinned-`ActionBar` convention for this SDK's
    /// sheets (`.regularMaterial` bar with a top hairline).
    private var footer: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.filename)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(metaLine)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 0)

            // Not tinted with `theme.accentColor` on purpose: the only way out of
            // a modal has to stay legible no matter what accent an adopter sets,
            // so this uses the native bordered treatment over `.primary` — the
            // same choice `IssueStateCard` makes for its always-available action.
            Button("Done") { dismiss() }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .tint(.primary)
                .keyboardShortcut(.cancelAction)   // Escape on macOS
                .accessibilityHint("Closes the preview and returns to the report form.")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
    }

    private var metaLine: String {
        var pixelSize: (Int, Int)?
        if case .image(let image) = phase { pixelSize = (image.width, image.height) }
        return Self.metaLine(
            byteCount: attachment.data.count,
            mimeType: attachment.mimeType,
            pixelSize: pixelSize
        )
    }

    private func imageLabel(for image: CGImage) -> String {
        "Attachment \(attachment.filename), \(image.width) by \(image.height) pixels"
    }

    // MARK: Pure formatting (unit-tested)

    /// `"1024 × 768 · 812 KB · image/png"` — dimensions omitted when the bytes
    /// aren't a displayable image.
    static func metaLine(
        byteCount: Int,
        mimeType: String,
        pixelSize: (Int, Int)?
    ) -> String {
        var parts: [String] = []
        if let pixelSize { parts.append("\(pixelSize.0) × \(pixelSize.1)") }
        parts.append(formattedByteCount(byteCount))
        if !mimeType.isEmpty { parts.append(mimeType) }
        return parts.joined(separator: " · ")
    }

    static func formattedByteCount(_ count: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(count))
    }
}
