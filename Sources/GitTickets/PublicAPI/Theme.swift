import Foundation
import SwiftUI

/// Visual styling for the report form, "My Issues" list, and any other
/// GitTickets-provided UI.
///
/// Hosts apply via `.environment(\.gitTicketsTheme, .myAppTheme)` on whatever
/// view wraps the GitTickets UI, or set it once at ``Configuration/theme``.
///
/// Defaults inherit the host app's `Color.accentColor` and use system fonts —
/// most apps need no customization. The intent is *borrowed* appearance, not
/// imposed appearance.
public struct GitTicketsTheme: Sendable {

    /// Overrides the host app's `Color.accentColor`. `nil` (default) inherits.
    public var accentColor: Color?

    /// Font for headings and section titles.
    public var titleFont: Font

    /// Font for body text and form fields.
    public var bodyFont: Font

    /// Monospaced font for the diagnostics blob.
    public var monospacedFont: Font

    /// Corner radius for the form's grouped sections and the submit button.
    public var cornerRadius: CGFloat

    /// Optional header image displayed at the top of the report sheet.
    public var headerImage: GitTicketsImageSource?

    /// SwiftUI button style applied to the Submit button.
    public var submitButtonStyle: GitTicketsButtonStyle

    public init(
        accentColor: Color? = nil,
        titleFont: Font = .headline,
        bodyFont: Font = .body,
        monospacedFont: Font = .system(.caption, design: .monospaced),
        cornerRadius: CGFloat = 8,
        headerImage: GitTicketsImageSource? = nil,
        submitButtonStyle: GitTicketsButtonStyle = .borderedProminent
    ) {
        self.accentColor = accentColor
        self.titleFont = titleFont
        self.bodyFont = bodyFont
        self.monospacedFont = monospacedFont
        self.cornerRadius = cornerRadius
        self.headerImage = headerImage
        self.submitButtonStyle = submitButtonStyle
    }

    /// The default theme — inherits the host app's accent color and uses
    /// system fonts.
    public static let `default` = GitTicketsTheme()
}

/// Source for an optional image (e.g. ``GitTicketsTheme/headerImage``).
///
/// All cases are `Sendable`-safe: the `.named` case carries a bundle
/// identifier string rather than a `Bundle` reference, because `Bundle` is
/// a non-`Sendable` reference type and embedding one in this enum would be
/// a Sendable lie.
public enum GitTicketsImageSource: Sendable {

    /// An SF Symbol name, e.g. `"exclamationmark.bubble"`.
    case systemSymbol(String)

    /// An asset name; loaded from the bundle with the given identifier, or
    /// from `Bundle.main` when `bundleIdentifier` is `nil`.
    case named(String, bundleIdentifier: String? = nil)

    /// Raw image data (PNG or JPEG).
    case data(Data)
}

/// SwiftUI button style options exposed through the theme.
public enum GitTicketsButtonStyle: Sendable {
    case bordered
    case borderedProminent
    case plain
}

// MARK: - Environment integration

/// SwiftUI `EnvironmentKey` for the active ``GitTicketsTheme``.
@available(macOS 13.0, iOS 16.0, *)
public struct GitTicketsThemeKey: EnvironmentKey {
    public static let defaultValue: GitTicketsTheme = .default
}

@available(macOS 13.0, iOS 16.0, *)
extension EnvironmentValues {
    /// The active GitTickets theme.
    ///
    /// Set via `.environment(\.gitTicketsTheme, .myAppTheme)` on any view
    /// wrapping GitTickets UI. Defaults to ``GitTicketsTheme/default``.
    public var gitTicketsTheme: GitTicketsTheme {
        get { self[GitTicketsThemeKey.self] }
        set { self[GitTicketsThemeKey.self] = newValue }
    }
}
