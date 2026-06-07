//
//  GitTicketsSupportingViews.swift
//  GitTickets — view-redesign handoff
//
//  The composable pieces the two redesigned screens are built from. Each is
//  small, theme-driven, and cross-platform. Where an existing public building
//  block already does the job it's reused rather than reinvented — see the
//  `// EXISTING:` seams in `GitTicketsView` / `IssueDetailView`.
//

import SwiftUI

// MARK: - ReportKind presentation

@available(macOS 13.0, iOS 16.0, *)
extension ReportKind {
    var displayTitle: String {
        switch self {
        case .bug: return "Bug"
        case .featureRequest: return "Feature"
        case .question: return "Question"
        }
    }
    var hint: String {
        switch self {
        case .bug: return "Something's broken"
        case .featureRequest: return "An idea to improve"
        case .question: return "How does this work?"
        }
    }
    var symbol: String {
        switch self {
        case .bug: return "ladybug"
        case .featureRequest: return "lightbulb"
        case .question: return "questionmark.circle"
        }
    }
    /// Quiet semantic hue used only for the detail-view badge (never as a fill).
    var badgeColor: Color {
        switch self {
        case .bug: return GTSemantic.danger
        case .featureRequest: return GTSemantic.warning
        case .question: return GTSemantic.info
        }
    }
}

// MARK: - Kind picker (three selectable cards with icon + one-line hint)

@available(macOS 13.0, iOS 16.0, *)
struct KindPicker: View {
    @Binding var selection: ReportKind
    let theme: GitTicketsTheme

    var body: some View {
        // Cards sit in a row on macOS / regular width, stack on compact iOS.
        #if os(macOS)
        HStack(spacing: 8) { cards }
        #else
        VStack(spacing: 8) { cards }
        #endif
    }

    @ViewBuilder private var cards: some View {
        ForEach(ReportKind.allCases, id: \.self) { kind in
            KindCard(kind: kind, isSelected: kind == selection, theme: theme) {
                selection = kind
            }
        }
    }
}

@available(macOS 13.0, iOS 16.0, *)
struct KindCard: View {
    let kind: ReportKind
    let isSelected: Bool
    let theme: GitTicketsTheme
    let action: () -> Void

    private var accent: Color { theme.resolvedAccent }

    var body: some View {
        Button(action: action) {
            #if os(macOS)
            VStack(alignment: .leading, spacing: 7) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
            #else
            HStack(spacing: 12) {
                iconTile
                VStack(alignment: .leading, spacing: 1) {
                    Text(kind.displayTitle).font(.subheadline.weight(.semibold))
                    Text(kind.hint).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark").font(.footnote.weight(.bold)).foregroundStyle(accent)
                }
            }
            #endif
        }
        .buttonStyle(.plain)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
                .fill(isSelected ? theme.accentTint : GTSurface.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
                .strokeBorder(isSelected ? accent : GTSurface.hairline,
                              lineWidth: isSelected ? 1.5 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous))
        .animation(.easeInOut(duration: 0.12), value: isSelected)
    }

    #if os(macOS)
    @ViewBuilder private var content: some View {
        HStack {
            iconTile
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(accent)
            }
        }
        Text(kind.displayTitle).font(.subheadline.weight(.semibold))
        Text(kind.hint).font(.caption).foregroundStyle(.secondary)
    }
    #endif

    private var iconTile: some View {
        Image(systemName: kind.symbol)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(isSelected ? Color.white : Color.secondary)
            .frame(width: 30, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? accent : GTSurface.subtleFill)
            )
    }
}

// MARK: - Trust banner (top of the trust flow) — supersedes the raw PrivacyBanner look

@available(macOS 13.0, iOS 16.0, *)
struct TrustBanner: View {
    let message: String          // resolved PrivacyPolicy banner copy
    let isPublic: Bool
    let theme: GitTicketsTheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.resolvedAccent)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Label(isPublic ? "Public repository" : "Visible to maintainers",
                      systemImage: isPublic ? "globe" : "person.2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            }
            Spacer(minLength: 0)
        }
        .trustSurface(theme: theme)
    }
}

// MARK: - Consent row (docked above Submit; shares the banner's visual language)

@available(macOS 13.0, iOS 16.0, *)
struct ConsentRow: View {
    @Binding var consented: Bool
    let message: String
    let theme: GitTicketsTheme

    var body: some View {
        Button {
            consented.toggle()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(theme.resolvedAccent, lineWidth: 1.5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(consented ? theme.resolvedAccent : GTSurface.card)
                        )
                        .frame(width: 22, height: 22)
                    if consented {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(message).font(.footnote).foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Same place the banner points to. Required before you submit.")
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .trustSurface(theme: theme)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(consented ? [.isSelected, .isButton] : .isButton)
    }
}

/// The shared accent-tinted surface that visually links the banner & consent.
@available(macOS 13.0, iOS 16.0, *)
private struct TrustSurface: ViewModifier {
    let theme: GitTicketsTheme
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: theme.cornerRadius + 1, style: .continuous)
                    .fill(theme.accentTint)
            )
            .overlay(
                RoundedRectangle(cornerRadius: theme.cornerRadius + 1, style: .continuous)
                    .strokeBorder(theme.resolvedAccent.opacity(0.28), lineWidth: 1)
            )
    }
}
@available(macOS 13.0, iOS 16.0, *)
private extension View {
    func trustSurface(theme: GitTicketsTheme) -> some View { modifier(TrustSurface(theme: theme)) }
}

// MARK: - Diagnostics card (expanded by default; redactions highlighted)

@available(macOS 13.0, iOS 16.0, *)
struct DiagnosticsCard: View {
    let blobText: String
    @Binding var isExpanded: Bool
    let theme: GitTicketsTheme

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(theme.resolvedAccent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Diagnostics").font(.footnote.weight(.semibold))
                        Text("Attached as-is. Highlighted values are redacted on-device.")
                            .font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().overlay(GTSurface.hairline)
                ScrollView {
                    Text(DiagnosticsRendering.highlighted(blobText, accent: theme.resolvedAccent))
                        .font(theme.monospacedFont)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14).padding(.vertical, 12)
                }
                .frame(maxHeight: 220)
                .background(GTSurface.ground)

                Divider().overlay(GTSurface.hairline)
                HStack(spacing: 6) {
                    Image(systemName: "checkmark").font(.caption2.weight(.bold))
                        .foregroundStyle(GTSemantic.success)
                    Text("Redacted on-device — what you see is exactly what's sent.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(GTSemantic.warning.opacity(0.16))
                            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(GTSemantic.warning, lineWidth: 1))
                            .frame(width: 9, height: 9)
                        Text("redacted").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
            }
        }
        .cardSurface(theme: theme)
    }
}

// MARK: - Generic card surface

@available(macOS 13.0, iOS 16.0, *)
struct CardSurface: ViewModifier {
    let theme: GitTicketsTheme
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: theme.cornerRadius + 1, style: .continuous)
                    .fill(GTSurface.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: theme.cornerRadius + 1, style: .continuous)
                    .strokeBorder(GTSurface.hairline, lineWidth: 1)
            )
    }
}
@available(macOS 13.0, iOS 16.0, *)
extension View {
    func cardSurface(theme: GitTicketsTheme) -> some View { modifier(CardSurface(theme: theme)) }
}
