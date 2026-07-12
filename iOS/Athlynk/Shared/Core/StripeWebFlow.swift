//
//  StripeWebFlow.swift
//  Opens a Stripe-hosted URL (Connect onboarding Account Link, or a Checkout
//  Session) in a system web view and waits for it to redirect back into the
//  app via a custom URL scheme. Both apps reuse the exact same
//  backend-generated hosted URLs as the web app — no Stripe SDK dependency,
//  no PaymentSheet/PaymentIntent handling on-device.
//

import AuthenticationServices
import UIKit

@MainActor
final class StripeWebFlow: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    /// Presents `url` and suspends until Stripe redirects to a URL whose
    /// scheme matches `callbackScheme` (e.g. "athlynkcoach", "athlynk").
    /// Returns the callback URL (so the caller can read query items like
    /// `session_id`), or throws if the user cancels/dismisses.
    func run(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: error ?? URLError(.cancelled))
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            self.session = session
            session.start()
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                .first ?? ASPresentationAnchor()
        }
    }
}
