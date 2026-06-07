import SwiftUI
import AuthenticationServices

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// The OAuth Device Flow sheet — shown when ``GitTickets/submit(_:)`` throws
/// ``GitTicketsError/deviceFlowNotAuthorized`` and the form needs to prompt the
/// user to sign in. Implements the UX recipe from
/// [[Footgun — iOS Device Flow Return-to-App UX]]:
///
/// - Calls ``DeviceFlowCoordinator/requestAuthorization()`` on appear.
/// - Surfaces the `user_code` in the sheet so the user can read it off if the
///   browser handoff fails.
/// - Opens `ASWebAuthenticationSession` with `verificationURIComplete` (the
///   user code is pre-filled) and `prefersEphemeralWebBrowserSession = true`
///   so no logged-in github.com identity leaks into the OAuth grant.
/// - Polls in parallel; when the token arrives, writes it to ``TokenStore``,
///   cancels the auth session, and calls ``onComplete``. The sheet stays open
///   the whole time so the user comes back to the same in-app view.
///
/// Concurrency: marked `@MainActor` because it touches AppKit/UIKit window
/// state and the auth session's completion handler must run on the main
/// thread.
@available(macOS 13.0, iOS 16.0, *)
@MainActor
public struct DeviceFlowSheet: View {

    let clientID: String
    let scopes: [DeviceFlowScope]
    let tokenStore: TokenStore
    let coordinator: DeviceFlowCoordinator
    let onComplete: (Result<Void, GitTicketsError>) -> Void

    @State private var phase: Phase = .requesting
    @State private var pollTask: Task<Void, Never>?

    /// Holds the auth session strongly so it survives the duration of the
    /// SwiftUI view's lifecycle — `ASWebAuthenticationSession` doesn't retain
    /// itself, so without this the browser modal dismisses the moment the
    /// `start()` call returns.
    @State private var sessionBox = WebAuthSessionBox()

    private let contextProvider = PresentationContextProvider()

    public init(
        clientID: String,
        scopes: [DeviceFlowScope] = [.publicRepo],
        onComplete: @escaping (Result<Void, GitTicketsError>) -> Void
    ) {
        self.clientID = clientID
        self.scopes = scopes
        self.tokenStore = TokenStore()
        self.coordinator = DeviceFlowCoordinator(clientID: clientID, scopes: scopes)
        self.onComplete = onComplete
    }

    /// Test-only initializer. Lets tests inject a per-test `TokenStore` (so the
    /// process-wide Keychain isn't polluted) and a coordinator wired to
    /// `MockURLProtocol`.
    init(
        clientID: String,
        scopes: [DeviceFlowScope],
        tokenStore: TokenStore,
        coordinator: DeviceFlowCoordinator,
        onComplete: @escaping (Result<Void, GitTicketsError>) -> Void
    ) {
        self.clientID = clientID
        self.scopes = scopes
        self.tokenStore = tokenStore
        self.coordinator = coordinator
        self.onComplete = onComplete
    }

    private enum Phase: Equatable {
        case requesting
        case waiting(DeviceFlowAuthorization)
        case failed(String)
        case done
    }

    public var body: some View {
        VStack(alignment: .center, spacing: 20) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("Sign in with GitHub")
                .font(.title3.weight(.semibold))

            content
        }
        .padding(24)
        .frame(minWidth: 360)
        .onDisappear {
            pollTask?.cancel()
            sessionBox.cancel()
        }
        .task {
            await startFlow()
        }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .requesting:
            VStack(spacing: 10) {
                ProgressView()
                Text("Asking GitHub for a sign-in code\u{2026}")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .waiting(let auth):
            VStack(spacing: 14) {
                Text("Enter this code on GitHub:")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(auth.userCode)
                    .font(.system(.title2, design: .monospaced).weight(.bold))
                    .textSelection(.enabled)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.gray.opacity(0.12))
                    )
                Text("A browser window opened — we'll detect the sign-in automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Reopen browser") {
                    presentAuth(url: auth.verificationURIComplete)
                }
                .buttonStyle(.borderless)
                ProgressView()
                    .controlSize(.small)
            }
        case .failed(let message):
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .done:
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.green)
                Text("Signed in.")
                    .font(.callout)
            }
        }
    }

    // MARK: - Flow

    private func startFlow() async {
        do {
            let auth = try await coordinator.requestAuthorization()
            phase = .waiting(auth)
            presentAuth(url: auth.verificationURIComplete)
            pollTask = Task { await pollLoop(authorization: auth) }
        } catch let error as GitTicketsError {
            phase = .failed(String(describing: error))
            onComplete(.failure(error))
        } catch {
            phase = .failed(String(describing: error))
            onComplete(.failure(.payloadInvalid(reason: "Device Flow request failed: \(error)")))
        }
    }

    private func pollLoop(authorization: DeviceFlowAuthorization) async {
        do {
            let token = try await coordinator.pollForToken(authorization: authorization)
            try tokenStore.write(token)
            sessionBox.cancel()
            phase = .done
            onComplete(.success(()))
        } catch let error as GitTicketsError {
            phase = .failed(String(describing: error))
            onComplete(.failure(error))
        } catch {
            phase = .failed(String(describing: error))
            onComplete(.failure(.payloadInvalid(reason: "Device Flow polling failed: \(error)")))
        }
    }

    /// Opens an `ASWebAuthenticationSession` with `prefersEphemeralWebBrowserSession`
    /// set so the user's logged-in github.com cookie jar doesn't leak into the OAuth
    /// grant (would let the OAuth App act as whichever user the browser was already
    /// signed in as — surprising and unwanted for a "sign in fresh" flow).
    private func presentAuth(url: URL) {
        sessionBox.cancel()
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: nil) { _, _ in
            // Device Flow doesn't use callback URLs — the polling loop is the
            // signal that succeeded. We deliberately ignore this completion.
        }
        session.prefersEphemeralWebBrowserSession = true
        session.presentationContextProvider = contextProvider
        sessionBox.session = session
        _ = session.start()
    }
}

/// Holds a single `ASWebAuthenticationSession` and cancels the previous one
/// when replaced. `@unchecked Sendable` is safe because all mutation happens
/// on the main thread — the field is only touched from `@MainActor` view code
/// and from auth-session completion handlers, which Apple posts on the main
/// queue.
@available(macOS 13.0, iOS 16.0, *)
final class WebAuthSessionBox: @unchecked Sendable {
    var session: ASWebAuthenticationSession?

    func cancel() {
        session?.cancel()
        session = nil
    }
}

/// Bridges `ASWebAuthenticationSession` to the host app's window — required so
/// the auth modal has something to present from. Cross-platform window
/// lookup: `NSApplication.shared.keyWindow` on macOS, the first key window of
/// the foreground scene on iOS.
@available(macOS 13.0, iOS 16.0, *)
final class PresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if canImport(AppKit)
        return NSApplication.shared.keyWindow
            ?? NSApplication.shared.windows.first
            ?? ASPresentationAnchor()
        #elseif canImport(UIKit)
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.windows.first { $0.isKeyWindow }
            ?? scene?.windows.first
            ?? ASPresentationAnchor()
        #else
        return ASPresentationAnchor()
        #endif
    }
}
