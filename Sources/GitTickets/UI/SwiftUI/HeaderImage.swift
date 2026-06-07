import SwiftUI

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Renders a ``GitTicketsImageSource`` through whichever platform image
/// type the current OS provides. Internal — adopters supply the source via
/// ``GitTicketsTheme/headerImage`` rather than constructing this view
/// directly.
///
/// The three source cases map as follows:
/// - `.systemSymbol(name)` → `Image(systemName: name)`.
/// - `.named(name, bundleIdentifier:)` → `Image(name, bundle: <looked-up>)`,
///   falling back to `Bundle.main` when the identifier doesn't resolve.
/// - `.data(bytes)` → `NSImage(data:)` / `UIImage(data:)` wrapped in
///   `Image(nsImage:)` / `Image(uiImage:)`. Returns the system-symbol
///   fallback when the bytes don't decode.
@available(macOS 13.0, iOS 16.0, *)
struct HeaderImage: View {

    let source: GitTicketsImageSource

    var body: some View {
        image
    }

    @ViewBuilder private var image: some View {
        switch source {
        case .systemSymbol(let name):
            Image(systemName: name)
        case .named(let name, let bundleIdentifier):
            Image(name, bundle: Self.resolveBundle(identifier: bundleIdentifier))
        case .data(let data):
            if let decoded = Self.makeImage(from: data) {
                decoded.resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "exclamationmark.bubble")
            }
        }
    }

    /// Looks up the bundle by identifier; falls back to `Bundle.main` when
    /// the identifier is `nil` or doesn't resolve (an asset declared in the
    /// host's main bundle is the most common case).
    static func resolveBundle(identifier: String?) -> Bundle {
        guard let identifier else { return .main }
        return Bundle(identifier: identifier) ?? .main
    }

    /// Decodes raw image bytes into a SwiftUI `Image`. Returns `nil` when the
    /// platform decoder rejects the bytes; mirrors ``ScreenshotThumbnail``'s
    /// approach for the same problem.
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
