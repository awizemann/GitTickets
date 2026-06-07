//
//  GitTicketsView.swift
//  GitTickets — view-redesign handoff
//
//  The redesigned report form. Reads its repo coordinates, theme, and the
//  diagnostics / privacy policies from `GitTickets.configuration`, collects
//  the diagnostics blob once on appear (so "what you see == what we send"
//  holds), and submits through `GitTickets.submit(_:)`.
//
//  Visual hierarchy reads top-to-bottom as:
//      privacy / trust  →  what's wrong  →  what we'll send  →  submit
//  The privacy banner (top) and consent row (docked above Submit) share one
//  accent-tinted surface so they read as a single trust flow.
//
//  macOS 13+ / iOS 16+. SwiftUI only.
//

import SwiftUI

@available(macOS 13.0, iOS 16.0, *)
public struct GitTicketsView: View {

    /// Which field treatment to use. Locked to `.flat` (Option B) — flat
    /// bordered fields with focus rings. See reference render §1B.
    private let fieldStyle: GitTicketsFieldStyle = .flat

    @Environment(\.gitTicketsTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    private let configuration: Configuration?
    private let onSubmitted: (SubmittedIssue) -> Void

    public init(
        configuration: Configuration? = GitTickets.configuration,
        onSubmitted: @escaping (SubmittedIssue) -> Void = { _ in }
    ) {
        self.configuration = configuration
        self.onSubmitted = onSubmitted
    }

    // MARK: Form state
    @State private var kind: ReportKind = .bug
    @State private var title: String = ""
    @State private var bodyText: String = ""
    @State private var consented = false
    @State private var diagnosticsExpanded = true   // transparency: always open by default
    @State private var diagnostics: DiagnosticsBlob?
    @State private var screenshot: Data?
    @State private var attachments: [ReportAttachment] = []
    @State private var isSubmitting = false
    @State private var submitError: String?

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    privacySection
                    whatsWrongSection
                    diagnosticsSection
                }
                .padding(20)
                .frame(maxWidth: 640, alignment: .leading)   // calm reading column on wide windows
                .frame(maxWidth: .infinity)
            }
            .background(GTSurface.ground)
            .navigationTitle("Report an issue")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    // Consent docked just above the action bar — closes the trust flow.
                    if requiresConsent {
                        ConsentRow(consented: $consented, message: consentMessage, theme: theme)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)
                            .background(GTSurface.ground)
                    }
                    ActionBar(
                        canSubmit: canSubmit,
                        isSubmitting: isSubmitting,
                        theme: theme,
                        onCancel: { dismiss() },
                        onSubmit: submit
                    )
                }
            }
            .toolbar {
                #if os(macOS)
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                #endif
            }
        }
        .task { collectDiagnosticsIfNeeded() }
        .alert("Couldn't submit", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(submitError ?? "Something went wrong. Please try again.")
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            theme.headerIcon()
                .frame(width: 26, height: 26)
                .foregroundStyle(theme.resolvedAccent)
                .padding(9)
                .background(
                    RoundedRectangle(cornerRadius: theme.cornerRadius + 1, style: .continuous)
                        .fill(theme.accentTint)
                )
            VStack(alignment: .leading, spacing: 3) {
                #if os(macOS)
                Text("Report an issue").font(theme.titleFont).fontWeight(.bold)
                #endif
                Text("Tell us what happened — it lands as a GitHub issue we can reply to.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GTSectionLabel(text: "Privacy")
            TrustBanner(message: bannerMessage, isPublic: isPublicRepo, theme: theme)
        }
    }

    private var whatsWrongSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            GTSectionLabel(text: "What's wrong")
            KindPicker(selection: $kind, theme: theme)
            DetailsSection(
                title: $title,
                bodyText: $bodyText,
                attachmentCount: attachments.count,
                hasScreenshot: screenshot != nil,
                style: fieldStyle,
                theme: theme,
                addAttachment: addAttachment,
                thumbnails: { AnyView(attachmentThumbnails) }
            )
        }
    }

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            GTSectionLabel(text: "Diagnostics we'll attach")
            DiagnosticsCard(
                blobText: diagnostics?.text ?? "Collecting diagnostics…",
                isExpanded: $diagnosticsExpanded,
                theme: theme
            )
        }
    }

    /// EXISTING: render the host's `ScreenshotThumbnail` for the screenshot
    /// and any image attachments. Swap the placeholders for your component:
    ///   ScreenshotThumbnail(data: data) { remove(...) }
    private var attachmentThumbnails: some View {
        HStack(spacing: 8) {
            if let shot = screenshot {
                // ScreenshotThumbnail(data: shot)
                thumbnailPlaceholder
                let _ = shot
            }
            ForEach(Array(attachments.enumerated()), id: \.offset) { _, attachment in
                // ScreenshotThumbnail(data: attachment.data)
                thumbnailPlaceholder
                let _ = attachment
            }
        }
    }

    private var thumbnailPlaceholder: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(GTSurface.subtleFill)
            .frame(width: 52, height: 52)
            .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(GTSurface.hairline))
    }

    // MARK: Derived

    private var isPublicRepo: Bool { configuration?.repo.visibility != .private }
    private var requiresConsent: Bool { configuration?.privacy.requireExplicitConsent ?? true }

    private var repoSlug: String {
        guard let repo = configuration?.repo else { return "this repository" }
        return "\(repo.owner)/\(repo.name)"
    }

    /// Tightened privacy banner copy (honors a host override when set).
    private var bannerMessage: String {
        if let custom = configuration?.privacy.bannerText { return custom }
        return isPublicRepo
            ? "Your report is filed publicly to \(repoSlug) — anyone can read it."
            : "Your report is visible to the maintainers of \(repoSlug)."
    }

    private var consentMessage: String {
        isPublicRepo
            ? "I understand this report and the diagnostics above will be posted publicly to \(repoSlug)."
            : "I understand this report and the diagnostics above will be posted to \(repoSlug)."
    }

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && (!requiresConsent || consented)
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { submitError != nil }, set: { if !$0 { submitError = nil } })
    }

    // MARK: Actions

    private func collectDiagnosticsIfNeeded() {
        guard diagnostics == nil, let policy = configuration?.diagnostics else { return }
        // Synchronous per DiagnosticsCollector's API; cheap enough for .task.
        diagnostics = DiagnosticsCollector.collect(policy: policy, logger: configuration?.logger)
    }

    /// EXISTING: present the host image picker (PhotosPicker on iOS,
    /// NSOpenPanel on macOS) and append a `ReportAttachment` / set `screenshot`.
    private func addAttachment() {
        // Wire to your existing attachment flow.
    }

    private func submit() {
        guard !isSubmitting else { return }
        isSubmitting = true
        submitError = nil
        let report = Report(
            kind: kind,
            title: title,
            body: bodyText,
            screenshot: screenshot,
            attachments: attachments,
            includeDiagnostics: diagnostics != nil,
            diagnosticsBlob: diagnostics?.text
        )
        Task {
            do {
                let issue = try await GitTickets.submit(report)
                await MainActor.run {
                    isSubmitting = false
                    onSubmitted(issue)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    submitError = (error as? GitTicketsError)?.localizedDescription
                        ?? error.localizedDescription
                }
            }
        }
    }
}
