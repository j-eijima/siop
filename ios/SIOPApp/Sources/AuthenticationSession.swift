import SIOPKit
import SwiftUI
import UIKit

/// Drives one authentication request through consent to the response
/// delivered back to the RP (OpenID Connect Core 1.0 Section 7.3-7.4).
@MainActor
final class AuthenticationSession: ObservableObject {
    enum Phase {
        case idle
        case consent(AuthorizationRequest)
        /// The response is built and the redirect is being opened.
        case delivering(clientID: String)
        case sent(clientID: String, redirectURL: URL)
        case declined(clientID: String)
        /// The response was built but could not be delivered to the RP.
        case undeliverable(clientID: String, redirectURL: URL)
        case failed(String)
    }

    /// There is no single identity: a separate key, and so a separate subject,
    /// is presented to each RP.
    struct KeyState {
        /// False when the Keychain was unavailable and in-memory keys are in
        /// use, which means subjects will not survive a relaunch.
        let isPersistent: Bool
    }

    private static let keyTag = "jp.co.pendako.siop.key"

    @Published private(set) var phase: Phase = .idle
    private(set) var keyState: KeyState?

    private var op: SelfIssuedOP?

    /// Opening a redirect completes asynchronously. Anything that moves on from
    /// the request in flight bumps this, so a completion that lands afterwards
    /// cannot overwrite whatever replaced it.
    private var requestGeneration = 0

    /// `open` delivers the response to the RP, reporting whether anything
    /// could handle the URL. Injected so the delivery race can be tested
    /// without a real redirect.
    init(
        keyStore: SIOPKeyStore? = nil,
        open: @escaping (URL, @escaping (Bool) -> Void) -> Void = { url, completion in
            UIApplication.shared.open(url, completionHandler: completion)
        }
    ) {
        self.openURL = open
        if let keyStore {
            op = SelfIssuedOP(keyStore: keyStore)
            keyState = KeyState(isPersistent: false)
        } else {
            let (store, isPersistent) = Self.makeKeyStore()
            op = SelfIssuedOP(keyStore: store)
            keyState = KeyState(isPersistent: isPersistent)
        }
    }

    private let openURL: (URL, @escaping (Bool) -> Void) -> Void

    /// Prefers Keychain-backed keys so subjects stay stable across launches,
    /// falling back to ephemeral ones so the app remains usable.
    private static func makeKeyStore() -> (SIOPKeyStore, Bool) {
        let keychain = KeychainKeyStore(tagPrefix: keyTag)
        do {
            // Proves the Keychain is usable before relying on it for every RP.
            _ = try keychain.keyProvider(for: "https://self-issued.me/probe")
            return (keychain, true)
        } catch {
            return (EphemeralKeyStore(), false)
        }
    }

    /// The identifier already established with `clientID`, or nil if this RP
    /// has not been answered before.
    ///
    /// Deliberately does not create one: `client_id` comes from whoever sent
    /// the request, and making a key costs an RSA generation and a permanent
    /// Keychain entry. A stream of unanswered requests must not be able to
    /// fill the Keychain or stall the screen.
    func establishedSubject(for clientID: String) -> String? {
        try? op?.keyStore.existingSubject(for: clientID)
    }

    // MARK: - Request handling

#if DEBUG
    /// Launch argument used by the UI tests to hand the app a request
    /// directly. `XCUIApplication.open(_:)` does not deliver the URL on every
    /// iOS version, and those tests are about the consent screen and the
    /// response, not about URL routing — `EndToEndRPTests` covers the real
    /// `openid:` route through Safari.
    static let requestLaunchArgument = "-siopRequestURL"

    func receiveLaunchRequestIfProvided() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: Self.requestLaunchArgument),
              arguments.index(after: flag) < arguments.endIndex,
              let url = URL(string: arguments[arguments.index(after: flag)])
        else { return }
        receive(url)
    }
#endif

    func receive(_ url: URL) {
        requestGeneration += 1
        do {
            phase = .consent(try AuthorizationRequest(url: url))
        } catch {
            phase = .failed(Self.describe(error))
        }
    }

    func approve(_ request: AuthorizationRequest) {
        guard let op else {
            phase = .failed("鍵が利用できません")
            return
        }
        do {
            let response = try op.respond(to: request)
            deliver(response.redirectURL, to: request.clientID) { clientID, url in
                .sent(clientID: clientID, redirectURL: url)
            }
        } catch {
            phase = .failed(Self.describe(error))
        }
    }

    /// Section 3.1.2.6: tell the RP the user declined rather than leaving it hanging.
    func decline(_ request: AuthorizationRequest) {
        do {
            let response = try AuthenticationErrorResponse(request: request)
            deliver(response.redirectURL, to: request.clientID) { clientID, _ in
                .declined(clientID: clientID)
            }
        } catch {
            phase = .failed(Self.describe(error))
        }
    }

    /// Hands the response to the RP, reporting the outcome rather than assuming
    /// one. A `client_id` may name any scheme (Section 7.2), including one no
    /// installed app handles, so the redirect can legitimately fail to open.
    private func deliver(
        _ redirectURL: URL,
        to clientID: String,
        onSuccess: @escaping (String, URL) -> Phase
    ) {
        let generation = requestGeneration
        // Leaving the consent screen up would let the buttons be pressed again
        // while the first response is still on its way.
        phase = .delivering(clientID: clientID)

        openURL(redirectURL) { [weak self] opened in
            guard let self, generation == self.requestGeneration else { return }
            self.phase = opened
                ? onSuccess(clientID, redirectURL)
                : .undeliverable(clientID: clientID, redirectURL: redirectURL)
        }
    }



    func reset() {
        requestGeneration += 1
        phase = .idle
    }

    // MARK: - Errors

    private static func describe(_ error: Error) -> String {
        guard let error = error as? SIOPError else {
            return String(describing: error)
        }
        switch error {
        case let .invalidRequest(reason): return "リクエストが不正です: \(reason)"
        case let .unsupportedResponseType(type): return "未対応の response_type です: \(type)"
        case .invalidScope: return "scope に openid が含まれていません"
        case let .keyGenerationFailed(reason): return "鍵の生成に失敗しました: \(reason ?? "不明")"
        case let .signingFailed(reason): return "署名に失敗しました: \(reason ?? "不明")"
        case .derParsingFailed: return "鍵の解析に失敗しました"
        case .invalidKey: return "鍵が不正です"
        case let .invalidToken(reason): return "ID Token が不正です: \(reason)"
        }
    }
}
