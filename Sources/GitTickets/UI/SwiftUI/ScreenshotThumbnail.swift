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
@available(macOS 13.0, iOS 16.0, *)
struct ScreenshotThumbnail: View {

    let filename: String
    let data: Data
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            preview
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.secondary.opacity(0.3))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(filename)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(byteCountFormatted)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Remove", role: .destructive, action: onRemove)
                .buttonStyle(.borderless)
        }
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
