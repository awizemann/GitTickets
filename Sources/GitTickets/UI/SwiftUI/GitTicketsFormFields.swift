//
//  GitTicketsFormFields.swift
//  GitTickets — view-redesign handoff
//
//  The "What's wrong" inputs. Two field treatments are provided; flip
//  `GitTicketsView.fieldStyle` to choose. Option A (inset grouped) is the
//  default shown in the reference render; Option B (flat bordered) is the
//  quieter, macOS-document alternative.
//

import SwiftUI

/// Which texture the form fields use. See the reference render, section 1B.
public enum GitTicketsFieldStyle: Sendable {
    case insetGrouped   // A — iOS-Settings grouped card with dividers
    case flat           // B — separate bordered fields with focus rings
}

@available(macOS 13.0, iOS 16.0, *)
struct DetailsSection: View {
    @Binding var title: String
    @Binding var bodyText: String
    let attachmentCount: Int
    let hasScreenshot: Bool
    let style: GitTicketsFieldStyle
    let theme: GitTicketsTheme
    let addAttachment: () -> Void
    /// EXISTING: pass-through so the host's ScreenshotThumbnail can render.
    let thumbnails: () -> AnyView

    @FocusState private var focused: Field?
    private enum Field { case title, body }

    var body: some View {
        switch style {
        case .insetGrouped: insetGrouped
        case .flat:         flat
        }
    }

    // MARK: Option A — inset grouped
    private var insetGrouped: some View {
        VStack(spacing: 0) {
            row(label: "Title") {
                TextField("Short summary", text: $title)
                    .textFieldStyle(.plain).font(.callout)
                    .focused($focused, equals: .title)
            }
            Divider().overlay(GTSurface.hairline)
            row(label: "Description") {
                editor
            }
            Divider().overlay(GTSurface.hairline)
            row(label: "Attachments") { attachmentsRow }
        }
        .cardSurface(theme: theme)
    }

    private func row<Content: View>(label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold)).tracking(0.5)
                .foregroundStyle(.tertiary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    // MARK: Option B — flat bordered fields
    private var flat: some View {
        VStack(alignment: .leading, spacing: 12) {
            labeled("Title") {
                TextField("Short summary", text: $title)
                    .textFieldStyle(.plain).font(.callout)
                    .focused($focused, equals: .title)
                    .field(theme: theme, isFocused: focused == .title)
            }
            labeled("Description") {
                editor
                    .field(theme: theme, isFocused: focused == .body)
                HStack {
                    Spacer()
                    Text("\(bodyText.count) / 4000")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            labeled("Attachments") { attachmentsRow }
        }
    }

    private func labeled<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
    }

    // MARK: shared pieces
    private var editor: some View {
        TextEditor(text: $bodyText)
            .font(.callout)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 92)
            .focused($focused, equals: .body)
            .overlay(alignment: .topLeading) {
                if bodyText.isEmpty {
                    Text("What happened? What did you expect?")
                        .font(.callout).foregroundStyle(.tertiary)
                        .padding(.top, 8).padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
    }

    private var attachmentsRow: some View {
        HStack(spacing: 12) {
            Button(action: addAttachment) {
                Label("Add image", systemImage: "photo")
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(theme.accentTint)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(theme.resolvedAccent.opacity(0.4),
                                          style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    )
                    .foregroundStyle(theme.resolvedAccent)
            }
            .buttonStyle(.plain)

            // EXISTING: host's ScreenshotThumbnail(s) for screenshot + attachments
            if hasScreenshot || attachmentCount > 0 {
                thumbnails()
            }
        }
    }
}

// MARK: - Flat field chrome

@available(macOS 13.0, iOS 16.0, *)
private struct FieldChrome: ViewModifier {
    let theme: GitTicketsTheme
    let isFocused: Bool
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
                    .fill(GTSurface.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
                    .strokeBorder(isFocused ? theme.resolvedAccent : GTSurface.hairlineStrong,
                                  lineWidth: isFocused ? 1.5 : 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
                    .strokeBorder(theme.resolvedAccent.opacity(isFocused ? 0.28 : 0), lineWidth: 3)
                    .padding(-2)
            )
            .animation(.easeInOut(duration: 0.12), value: isFocused)
    }
}
@available(macOS 13.0, iOS 16.0, *)
private extension View {
    func field(theme: GitTicketsTheme, isFocused: Bool) -> some View {
        modifier(FieldChrome(theme: theme, isFocused: isFocused))
    }
}

// MARK: - Pinned action bar (Cancel + Submit, outside the ScrollView)

@available(macOS 13.0, iOS 16.0, *)
struct ActionBar: View {
    let canSubmit: Bool
    let isSubmitting: Bool
    let theme: GitTicketsTheme
    let onCancel: () -> Void
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button("Cancel", action: onCancel)
                .buttonStyle(.bordered)
                .controlSize(.large)
            Spacer(minLength: 0)
            Button(action: onSubmit) {
                HStack(spacing: 7) {
                    if isSubmitting {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "paperplane.fill")
                    }
                    Text(isSubmitting ? "Submitting…" : "Submit issue")
                }
                .fontWeight(.semibold)
            }
            .controlSize(.large)
            .disabled(!canSubmit || isSubmitting)
            .gitTicketsSubmitStyle(theme.submitButtonStyle, tint: theme.resolvedAccent)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider().overlay(GTSurface.hairline) }
    }
}
