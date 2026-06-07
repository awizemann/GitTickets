//
//  GitTicketsView.swift
//  GitTickets — redesigned report form.
//
//  Reads its repo coordinates, theme, and the diagnostics / privacy policies
//  from `GitTickets.configuration`, collects the diagnostics blob once on
//  appear (so "what you see == what we send" holds), and submits through
//  `GitTickets.submit(_:)`.
//
//  Visual hierarchy reads top-to-bottom as:
//      privacy / trust  →  what's wrong  →  what we'll send  →  submit
//  The privacy banner (top) and consent row (docked above Submit) share one
//  accent-tinted surface so they read as a single trust flow.
//
//  macOS 13+ / iOS 16+. SwiftUI only.
//

import SwiftUI
import UniformTypeIdentifiers

@available(macOS 13.0, iOS 16.0, *)
public struct GitTicketsView: View {

    /// Which field treatment to use. Locked to `.flat` (Option B) — flat
    /// bordered fields with focus rings. See design reference §1B.
    private let fieldStyle: GitTicketsFieldStyle = .flat

    @Environment(\.gitTicketsTheme) private var envTheme
    @Environment(\.dismiss) private var dismiss

    private let configuration: Configuration?
    private let onSubmitted: (SubmittedIssue) -> Void

    /// Theme the view actually paints with. Prefers the theme stored on the
    /// active ``Configuration`` (set at app launch via
    /// ``GitTickets/configure(_:)``); falls back to the SwiftUI environment
    /// value when no configuration is wired up — that's the test/preview path.
    /// Without this, `Configuration.theme` would be stored but never read,
    /// and adopters who only set the theme on the configuration would see
    /// the package's default accent.
    private var theme: GitTicketsTheme {
        configuration?.theme ?? envTheme
    }

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
    @State private var showingFileImporter = false
    @State private var attachmentError: String?

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    privacySection
                    whatsWrongSection
                    diagnosticsSection
                    if let attachmentError {
                        Label(attachmentError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: Self.allowedImageTypes,
                allowsMultipleSelection: false,
                onCompletion: handleFileImport
            )
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
                addAttachment: { showingFileImporter = true },
                thumbnails: { AnyView(attachmentThumbnails) }
            )
        }
    }

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            GTSectionLabel(text: "Diagnostics we'll attach")
            DiagnosticsCard(
                blobText: diagnostics?.text ?? "Collecting diagnostics\u{2026}",
                isExpanded: $diagnosticsExpanded,
                theme: theme
            )
        }
    }

    /// Renders the host's ``ScreenshotThumbnail`` for the screenshot and any
    /// image attachments. Tap-to-remove is wired through each thumbnail's
    /// `onRemove` closure.
    private var attachmentThumbnails: some View {
        HStack(spacing: 8) {
            if let shot = screenshot {
                ScreenshotThumbnail(
                    filename: "screenshot.png",
                    data: shot,
                    onRemove: { screenshot = nil }
                )
                .frame(maxWidth: 200)
            }
            ForEach(Array(attachments.enumerated()), id: \.offset) { offset, attachment in
                ScreenshotThumbnail(
                    filename: attachment.filename,
                    data: attachment.data,
                    onRemove: { attachments.remove(at: offset) }
                )
                .frame(maxWidth: 200)
            }
        }
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

    /// Handles the SwiftUI `fileImporter` result: reads the file, validates
    /// the size against the relay's 5 MB ceiling, and appends to
    /// `attachments`. Security-scoped resource bracketing is required on iOS
    /// for files outside the app container.
    private func handleFileImport(_ result: Result<[URL], Error>) {
        attachmentError = nil
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }
            let didStart = url.startAccessingSecurityScopedResource()
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            if data.count > Self.attachmentByteLimit {
                attachmentError = "That image is \(data.count / 1024) KB — the relay caps attachments at \(Self.attachmentByteLimit / 1_048_576) MB."
                return
            }
            attachments.append(ReportAttachment(
                filename: url.lastPathComponent,
                mimeType: Self.mimeType(for: url),
                data: data
            ))
        } catch {
            attachmentError = "Couldn't read that file: \(error.localizedDescription)"
        }
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
                    submitError = (error as? GitTicketsError)?.description
                        ?? error.localizedDescription
                }
            }
        }
    }

    // MARK: - Static helpers

    static let attachmentByteLimit = 5 * 1_048_576
    static let allowedImageTypes: [UTType] = [.png, .jpeg, .heic, .gif, .webP]

    static func mimeType(for url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension) {
            if type.conforms(to: .png) { return "image/png" }
            if type.conforms(to: .jpeg) { return "image/jpeg" }
            if type.conforms(to: .heic) { return "image/heic" }
            if type.conforms(to: .gif) { return "image/gif" }
            if type.conforms(to: .webP) { return "image/webp" }
        }
        return "application/octet-stream"
    }
}
