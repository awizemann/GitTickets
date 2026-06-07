//
//  GitTicketsTheme+Support.swift
//  GitTickets — view-redesign handoff
//
//  Cross-platform glue the redesigned `GitTicketsView` and `IssueDetailView`
//  rely on. Everything here is driven by `GitTicketsTheme`, falls back to the
//  host app's `Color.accentColor`, and adapts to light/dark automatically by
//  resolving to native system surface colors (so the package keeps the
//  "borrowed appearance" promise instead of imposing a palette).
//
//  No third-party dependencies. macOS 13+ / iOS 16+.
//

import SwiftUI

// MARK: - Resolved theme convenience

@available(macOS 13.0, iOS 16.0, *)
extension GitTicketsTheme {

    /// The accent the UI should actually paint with: the theme override when
    /// set, otherwise the host app's accent color.
    var resolvedAccent: Color { accentColor ?? .accentColor }

    /// A low-alpha wash of the accent for trust surfaces (banner, consent,
    /// selected kind card). Derived from the accent — never a second hue.
    var accentTint: Color { resolvedAccent.opacity(0.12) }

    /// Builds the header glyph. Honors `headerImage`; defaults to a calm
    /// SF Symbol when the host didn't override it.
    @ViewBuilder
    func headerIcon() -> some View {
        switch headerImage {
        case .systemSymbol(let name):
            Image(systemName: name).resizable().scaledToFit()
        case .named(let name, let bundleID):
            Image(name, bundle: bundleID.flatMap { Bundle(identifier: $0) })
                .resizable().scaledToFit()
        case .data(let data):
            GitTicketsPlatformImage(data: data)
        case .none:
            Image(systemName: "exclamationmark.bubble").resizable().scaledToFit()
        }
    }
}

/// Renders raw image bytes cross-platform without leaking AppKit/UIKit types
/// to call sites.
@available(macOS 13.0, iOS 16.0, *)
struct GitTicketsPlatformImage: View {
    let data: Data
    var body: some View {
        #if os(macOS)
        if let img = NSImage(data: data) {
            Image(nsImage: img).resizable().scaledToFit()
        } else { Color.clear }
        #else
        if let img = UIImage(data: data) {
            Image(uiImage: img).resizable().scaledToFit()
        } else { Color.clear }
        #endif
    }
}

// MARK: - Native surface colors (calm, adaptive, no invented palette)

@available(macOS 13.0, iOS 16.0, *)
enum GTSurface {
    /// The sheet ground behind cards.
    static var ground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemGroupedBackground)
        #endif
    }
    /// Card / grouped-row surface that sits on `ground`.
    static var card: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }
    /// Hairline border — the system's separator equivalent.
    static var hairline: Color { Color.primary.opacity(0.09) }
    static var hairlineStrong: Color { Color.primary.opacity(0.14) }
    /// Quiet fill for unselected chips / icon tiles.
    static var subtleFill: Color { Color.primary.opacity(0.06) }
}

// MARK: - Diagnostics redaction highlighting

@available(macOS 13.0, iOS 16.0, *)
enum DiagnosticsRendering {

    /// Builds an `AttributedString` from the (already-redacted) diagnostics
    /// blob, visually highlighting every `[… redacted]` token and the
    /// `Bearer [token redacted]` form so the user can *see* what was scrubbed.
    /// Purely cosmetic — the underlying string is unchanged, preserving the
    /// "what you see == what we send" invariant.
    static func highlighted(_ text: String, accent: Color) -> AttributedString {
        var attributed = AttributedString(text)
        attributed.foregroundColor = .secondary

        // Matches "[email redacted]", "[ip redacted]", "[token redacted]", etc.
        guard let regex = try? NSRegularExpression(
            pattern: #"\[[^\]]*redacted\]"#, options: [.caseInsensitive]
        ) else { return attributed }

        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        for match in matches {
            if let range = Range(match.range, in: attributed) {
                attributed[range].foregroundColor = GTSemantic.warning
                attributed[range].backgroundColor = GTSemantic.warning.opacity(0.16)
                attributed[range].font = .system(.caption, design: .monospaced).weight(.semibold)
            }
        }
        return attributed
    }
}

// MARK: - Semantic accents for badges / state

@available(macOS 13.0, iOS 16.0, *)
enum GTSemantic {
    static let warning = Color(red: 0.85, green: 0.60, blue: 0.29)   // amber
    static let success = Color(red: 0.18, green: 0.58, blue: 0.42)   // green
    static let danger  = Color(red: 0.81, green: 0.35, blue: 0.32)   // red
    static let info    = Color(red: 0.29, green: 0.48, blue: 0.71)   // blue
}

// MARK: - Submit button style bridge

@available(macOS 13.0, iOS 16.0, *)
extension View {
    /// Applies the host-selected submit button style from the theme.
    @ViewBuilder
    func gitTicketsSubmitStyle(_ style: GitTicketsButtonStyle, tint: Color) -> some View {
        switch style {
        case .borderedProminent: self.buttonStyle(.borderedProminent).tint(tint)
        case .bordered:          self.buttonStyle(.bordered).tint(tint)
        case .plain:             self.buttonStyle(.plain)
        }
    }
}

// MARK: - Small reusable section label (the quiet eyebrow)

@available(macOS 13.0, iOS 16.0, *)
struct GTSectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(0.7)
            .foregroundStyle(.secondary)
    }
}
