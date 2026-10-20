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
//  macOS 14+ / iOS 18+. SwiftUI only.
//

import SwiftUI
import UniformTypeIdentifiers

public struct GitTicketsView: View {

    /// Which field treatment to use. Locked to `.flat` (Option B) — flat
    /// bordered fields with focus rings. See design reference §1B.
    private let fieldStyle: GitTicketsFieldStyle = .flat

    @Environment(\.gitTicketsTheme) private var envTheme
    @Environment(\.dismiss) private var dismiss

    private let configuration: Configuration?
    private let onSubmitted: (SubmittedIssue) -> Void
    private let showsToolbarCancel: Bool

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

    /// - Parameters:
    ///   - prefill: Opens the form with these values filled in. Everything
    ///     stays editable and nothing is sent until the person submits.
    ///   - showsToolbarCancel: Set `false` when the host's own container
    ///     already provides a Cancel, so the form doesn't add a second one to
    ///     the macOS toolbar. The Cancel in the bottom action bar stays.
    public init(
        configuration: Configuration? = GitTickets.configuration,
        prefill: TicketPrefill? = nil,
        showsToolbarCancel: Bool = true,
        onSubmitted: @escaping (SubmittedIssue) -> Void = { _ in }
    ) {
        self.configuration = configuration
        self.onSubmitted = onSubmitted
        self.showsToolbarCancel = showsToolbarCancel
        _kind = State(initialValue: prefill?.kind ?? .bug)
        _title = State(initialValue: prefill?.title ?? "")
        _bodyText = State(initialValue: prefill?.body ?? "")
        _hostDiagnostics = State(initialValue: Self.redactedHostDiagnostics(
            prefill?.diagnostics,
            policy: configuration?.diagnostics ?? .default
        ))
    }

    // MARK: Form state
    @State private var kind: ReportKind
    @State private var title: String
    @State private var bodyText: String
    /// Diagnostics supplied by the host via ``TicketPrefill``, already
    /// redacted. `nil` once the person removes them.
    @State private var hostDiagnostics: String?
    @State private var consented = false
    @State private var diagnosticsExpanded = true   // transparency: always open by default
    @State private var diagnostics: DiagnosticsBlob?
    @State private var screenshot: Data?
    /// True while a capture is in flight, so the control can show progress and
    /// a second tap cannot start an overlapping capture.
    @State private var isCapturingScreenshot = false
    /// Non-blocking explanation when a capture fails. Never prevents
    /// submission — the user can always add an image by hand instead.
    @State private var screenshotError: String?
    @State private var attachments: [ReportAttachment] = []
    @State private var isSubmitting = false
    @State private var submitError: String?
    @State private var showingFileImporter = false
    @State private var attachmentError: String?
    /// The pending attachment currently open at full size, if any. Holds a copy
    /// of the bytes, not an index — see ``PendingAttachment``.
    @State private var previewingAttachment: PendingAttachment?

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
                    // Informational, not a warning: a failed capture costs the
                    // user nothing — they can attach an image and submit.
                    if let screenshotError {
                        Label(screenshotError, systemImage: "camera.badge.ellipsis")
                            .foregroundStyle(.secondary)
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
                if showsToolbarCancel {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                #endif
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: Self.allowedImageTypes,
                allowsMultipleSelection: false,
                onCompletion: handleFileImport
            )
            // Submission is irreversible and (for a public repo) world-readable,
            // so a pending attachment can be opened at full size and checked
            // before Submit.
            .sheet(item: $previewingAttachment) { pending in
                AttachmentPreviewSheet(attachment: pending, theme: theme)
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
                addAttachment: { showingFileImporter = true },
                addScreenshot: allowsScreenshotCapture && screenshot == nil
                    ? { Task { await captureScreenshot() } }
                    : nil,
                isCapturingScreenshot: isCapturingScreenshot,
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
            if let hostDiagnostics {
                HostDiagnosticsCard(
                    text: hostDiagnostics,
                    theme: theme,
                    onRemove: { self.hostDiagnostics = nil }
                )
            }
        }
    }

    /// Captures the screen behind this form and attaches it.
    ///
    /// Uses ``ScreenshotCapture/captureExcludingReporter()`` rather than the
    /// public `capture()`, so the shot is the app underneath instead of a
    /// picture of this form covering the problem the user is reporting.
    ///
    /// Failure is never fatal. A missing Screen Recording permission on macOS
    /// is a shrug — the SDK does not nag for it — so the message points at
    /// "Add image" and the user submits regardless.
    private func captureScreenshot() async {
        guard !isCapturingScreenshot else { return }
        isCapturingScreenshot = true
        screenshotError = nil
        defer { isCapturingScreenshot = false }

        switch await ScreenshotCapture.captureExcludingReporter() {
        case .success(let data):
            screenshot = data
        case .failure(let error):
            screenshotError = ScreenshotCapture.failureMessage(for: error)
            // The adopter needs the real reason; the user does not.
            configuration?.logger?.log(
                level: .info,
                message: ScreenshotCapture.diagnosticMessage(for: error),
                error: nil
            )
        }
    }

    /// Renders the host's ``ScreenshotThumbnail`` for the screenshot and any
    /// image attachments. Tap-to-remove is wired through each thumbnail's
    /// `onRemove` closure; `onExpand` opens the full-size preview.
    ///
    /// Stacked vertically and uncapped, not side by side: each cell is a wide row
    /// (tile + filename + Remove), so several across the 640pt reading column
    /// squeezed the filename to an ellipsis and could truncate the *destructive*
    /// Remove label outright at large Dynamic Type sizes.
    private var attachmentThumbnails: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let shot = screenshot {
                ScreenshotThumbnail(
                    filename: Self.screenshotFilename,
                    data: shot,
                    onRemove: { screenshot = nil },
                    onExpand: {
                        previewingAttachment = PendingAttachment(
                            filename: Self.screenshotFilename,
                            mimeType: "image/png",
                            data: shot
                        )
                    }
                )
            }
            ForEach(Array(attachments.enumerated()), id: \.offset) { offset, attachment in
                ScreenshotThumbnail(
                    filename: attachment.filename,
                    data: attachment.data,
                    onRemove: { attachments.remove(at: offset) },
                    onExpand: {
                        previewingAttachment = PendingAttachment(
                            filename: attachment.filename,
                            mimeType: attachment.mimeType,
                            data: attachment.data
                        )
                    }
                )
            }
        }
    }

    // MARK: Derived

    /// Whether the form may offer screenshot capture. Defaults to `true` when
    /// no configuration is active, matching ``PrivacyPolicy/default``.
    private var allowsScreenshotCapture: Bool {
        configuration?.privacy.allowsScreenshotCapture ?? true
    }

    private var isPublicRepo: Bool { RepoVisibility.isPublic(configuration) }
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
        Self.consentMessage(
            override: configuration?.privacy.consentText,
            isPublic: isPublicRepo,
            repoSlug: repoSlug
        )
    }

    /// Consent copy. A non-empty host override wins; otherwise the default
    /// names the repo. Static so tests can pin both cases.
    static func consentMessage(override: String?, isPublic: Bool, repoSlug: String) -> String {
        if let override, !override.isEmpty { return override }
        return isPublic
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
            includeDiagnostics: diagnostics != nil || hostDiagnostics != nil,
            diagnosticsBlob: Self.combinedDiagnostics(
                collected: diagnostics?.text,
                host: hostDiagnostics
            )
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

    /// Runs host-supplied diagnostics through the same redactors as the
    /// collected blob. Blank text counts as none.
    static func redactedHostDiagnostics(_ text: String?, policy: DiagnosticsPolicy) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return RedactionPipeline.redact(trimmed, with: policy.redactors)
    }

    /// The blob that's sent: collected diagnostics first, then the host's.
    static func combinedDiagnostics(collected: String?, host: String?) -> String? {
        let parts = [collected, host].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    /// Display name for the auto-captured screenshot. Matches the name
    /// `RelaySubmitter` uploads it under, so the preview names the same file the
    /// issue will.
    static let screenshotFilename = "screenshot.png"

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
