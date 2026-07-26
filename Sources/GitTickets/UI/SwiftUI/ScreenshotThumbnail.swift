import SwiftUI

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Renders an attached image as a small thumbnail with a Remove button.
///
/// Falls back to a filename-only chip if the raw bytes can't decode into a
/// platform image — the form still surfaces the attachment, just without a
/// preview. Cross-platform: `NSImage` on macOS, `UIImage` on iOS.
struct ScreenshotThumbnail: View {

    let filename: String
    let data: Data
    let onRemove: () -> Void

    /// When non-`nil` the thumbnail tile becomes a real `Button` that opens the
    /// attachment at full size. Left `nil` the cell renders exactly as it did
    /// before v2.1.0 — inert, no badge, no extra accessibility element.
    var onExpand: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(filename)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(byteCountFormatted)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // One VoiceOver stop for "name, size" instead of two, and it no
            // longer repeats the filename the expand button just announced.
            .accessibilityElement(children: .combine)
            Spacer()
            Button("Remove", role: .destructive, action: onRemove)
                .buttonStyle(.borderless)
                // Several attachments would otherwise expose several identically
                // labelled destructive buttons.
                .accessibilityLabel("Remove \(filename)")
        }
    }

    /// The 48pt tile, wrapped in a `Button` when an expand action is supplied.
    ///
    /// A real `Button` (not an `onTapGesture`) on purpose: that is what makes
    /// the affordance an `AXButton` for VoiceOver on both platforms and puts it
    /// in the macOS key view loop under Full Keyboard Access. The Remove button
    /// stays a sibling rather than being nested inside this one, so hit-testing
    /// and the accessibility tree both stay unambiguous.
    @ViewBuilder private var thumbnail: some View {
        if let onExpand {
            Button(action: onExpand) { tile }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                // Short label, detail in the hint — VoiceOver reads label + trait
                // first, and this is also what a Voice Control user has to say
                // out loud. Worded to hold for a non-image / undecodable
                // attachment too: the sheet always opens and always says
                // something true about the file, so this is never a control that
                // does nothing.
                .accessibilityLabel("Preview \(filename)")
                // `help(_:)` sets the accessibility hint as well as the macOS
                // tooltip, so the two can't both be applied — one would silently
                // overwrite the other.
                #if os(macOS)
                .help("Preview at full size")
                #else
                .accessibilityHint("Opens the attachment at full size so you can check it before submitting.")
                #endif
        } else {
            tile
        }
    }

    private var tile: some View {
        preview
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.secondary.opacity(0.3))
            )
            .overlay(alignment: .bottomTrailing) {
                if onExpand != nil { expandBadge }
            }
    }

    /// Makes the tap target discoverable. Uses a material rather than a fixed
    /// color so it stays legible over any image content, in light or dark, under
    /// any adopter theme — the badge sits on top of arbitrary user pixels, so it
    /// can't inherit a surface color.
    private var expandBadge: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.primary)
            .padding(3)
            .background(Circle().fill(.regularMaterial))
            .padding(2)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var preview: some View {
        if let image = Self.makeImage(from: data) {
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Image(systemName: "photo")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.gray.opacity(0.1))
        }
    }

    private var byteCountFormatted: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(data.count))
    }

    /// Decodes the bytes into a SwiftUI `Image` using the platform's native
    /// image type. Returns `nil` for anything the platform decoder rejects.
    static func makeImage(from data: Data) -> Image? {
        #if canImport(AppKit)
        guard let ns = NSImage(data: data) else { return nil }
        return Image(nsImage: ns)
        #elseif canImport(UIKit)
        guard let ui = UIImage(data: data) else { return nil }
        return Image(uiImage: ui)
        #else
        return nil
        #endif
    }
}
