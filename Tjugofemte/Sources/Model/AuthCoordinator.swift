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

    var hasPendingFlow: Bool { continuation != nil }

    /// Returns the authorisation code once the user is back.
    func authorize(url: URL, state: String) async throws -> String {
        expectedState = state
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: Self.scheme) { [weak self] callback, error in
                Task { @MainActor in
                    if let callback { self?.finish(with: callback) }
                    else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin { self?.fail(.cancelled) }
                    else { self?.fail(.bankError(error?.localizedDescription ?? "unknown")) }
                }
            }
            session.prefersEphemeralWebBrowserSession = false  // share cookies with Safari in case BankID returns the user there
            session.presentationContextProvider = self
            self.session = session
            session.start()
        }
    }

    /// Second receive path, from `onOpenURL`. A URL that does not carry this flow's state nonce is ignored,
    /// so another app cannot cancel or spoof a pending login by opening the scheme.
    func handleOpenURL(_ url: URL) {
        guard url.scheme == Self.scheme, continuation != nil, stateMatches(url) else { return }
        session?.cancel()
        finish(with: url)
    }

    private func stateMatches(_ url: URL) -> Bool {
        guard let expected = expectedState else { return false }
        return queryValue(url, "state") == expected
    }

    private func queryValue(_ url: URL, _ name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }

    private func finish(with callback: URL) {
        guard stateMatches(callback) else { return fail(.stateMismatch) }
        if let error = queryValue(callback, "error") { return fail(.bankError(queryValue(callback, "error_description") ?? error)) }
        guard let code = queryValue(callback, "code") else { return fail(.noCode) }
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
