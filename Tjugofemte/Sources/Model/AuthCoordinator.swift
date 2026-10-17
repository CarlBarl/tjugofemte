import Foundation
import AuthenticationServices
import UIKit

/// Runs the bank authorisation in the system browser and receives the callback on either of two paths:
/// the ASWebAuthenticationSession completion, or the scene's open-URL handler when BankID returned the
/// user to Safari proper and Safari opened the custom scheme.
@MainActor
final class AuthCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let scheme = "tjugofemte"
    static let redirectURL = URL(string: "tjugofemte://callback")!

    enum Failure: Error, Equatable { case cancelled, stateMismatch, bankError(String), noCode }

    private var session: ASWebAuthenticationSession?
    private var continuation: CheckedContinuation<String, Error>?
    private var expectedState: String?

    /// Returns the authorisation code once the user is back.
    func authorize(url: URL, state: String) async throws -> String {
        expectedState = state
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: Self.scheme) { [weak self] callback, error in
                Task { @MainActor in
                    if let callback { self?.finish(with: callback) }
                    else if let error as? ASWebAuthenticationSessionError, error.code == .canceledLogin { self?.fail(.cancelled) }
                    else { self?.fail(.bankError(error?.localizedDescription ?? "unknown")) }
                }
            }
            session.prefersEphemeralWebBrowserSession = false  // share cookies with Safari in case BankID returns the user there
            session.presentationContextProvider = self
            self.session = session
            session.start()
        }
    }

    /// Second receive path, from `onOpenURL`.
    func handleOpenURL(_ url: URL) {
        guard url.scheme == Self.scheme else { return }
        session?.cancel()
        finish(with: url)
    }

    private func finish(with callback: URL) {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if let error = value("error") { return fail(.bankError(value("error_description") ?? error)) }
        guard value("state") == expectedState else { return fail(.stateMismatch) }
        guard let code = value("code") else { return fail(.noCode) }
        continuation?.resume(returning: code)
        cleanup()
    }

    private func fail(_ failure: Failure) {
        continuation?.resume(throwing: failure)
        cleanup()
    }

    private func cleanup() {
        continuation = nil
        session = nil
        expectedState = nil
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
        }
    }
}
