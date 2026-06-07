# Theming

`GitTicketsTheme` controls the form's visual appearance. Apply it via
either the `Configuration.theme` field or the `\.gitTicketsTheme`
environment value on any view that wraps the GitTickets UI.

> **Out-of-the-box look.** With no theme override, the form and detail views
> inherit the host app's `Color.accentColor` and use system semantic surface
> colors that adapt to light + dark. The neutral default is documented in
> [`design/design_handoff_gittickets_views_generic/`](../design/design_handoff_gittickets_views_generic/)
> — open `reference/GitTickets Redesign (Generic).html` in a browser to see
> the macOS + iOS frames the views are designed to.

```swift
extension GitTicketsTheme {
    static let myAppTheme = GitTicketsTheme(
        accentColor: Color("BrandAccent"),
        titleFont: .custom("Inter-Bold", size: 18, relativeTo: .headline),
        cornerRadius: 12,
        headerImage: .systemSymbol("ladybug.fill"),
        submitButtonStyle: .borderedProminent
    )
}

// Either at configure time:
GitTickets.configure(.init(repo: ..., auth: ..., theme: .myAppTheme))

// Or via the environment, on a per-presentation basis:
.sheet(isPresented: $showing) {
    GitTicketsView()
        .environment(\.gitTicketsTheme, .myAppTheme)
}
```

## Fields

| Field                 | Type                          | Default                             | Effect                                                        |
| --------------------- | ----------------------------- | ----------------------------------- | ------------------------------------------------------------- |
| `accentColor`         | `Color?`                      | `nil` (inherits host accent)        | The form's `tint` — buttons, focus rings, info icon.          |
| `titleFont`           | `Font`                        | `.headline`                         | The "Report an Issue" header.                                 |
| `bodyFont`            | `Font`                        | `.body`                             | Title field + description editor.                             |
| `monospacedFont`      | `Font`                        | `.system(.caption, design: .monospaced)` | The diagnostics blob text.                                  |
| `cornerRadius`        | `CGFloat`                     | `8`                                 | Banner background, diagnostics background, editor border.     |
| `headerImage`         | `GitTicketsImageSource?`      | `nil` (`exclamationmark.bubble`)    | Header icon, replaces the default symbol.                     |
| `submitButtonStyle`   | `GitTicketsButtonStyle`       | `.borderedProminent`                | One of `.bordered`, `.borderedProminent`, `.plain`.           |

## `GitTicketsImageSource` cases

```swift
.systemSymbol("ladybug.fill")
.named("BrandIcon")
.named("BrandIcon", bundleIdentifier: "com.myorg.brandassets")
.data(myPNGData)
```

The `.named` case falls back to `Bundle.main` when the supplied identifier
doesn't resolve. The `.data` case falls back to the default SF Symbol when
the bytes don't decode.

## Inheritance vs. override

The default theme inherits the host app's `Color.accentColor` and uses
system fonts. Most apps need no customization — pass `.default` (or
nothing). Override only the fields that matter.

## What's not in the theme yet

- Light/dark color overrides per-element. Today the form follows the host
  app's environment color scheme; per-component overrides aren't exposed.
- Custom localized strings (every label is in English). Adopters can
  override via the host app's `.environment(\.locale, ...)` if they ship
  localized resources that match SwiftUI's automatic lookup, but the SDK
  itself doesn't ship .strings files yet.

These are open issues for v1.1.
