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

    /// The self-issued identity this device presents to every RP.
    struct Identity {
        let subject: String
        let jwk: RSAPublicJWK
        /// False when the Keychain was unavailable and an in-memory key is in
        /// use, which means `subject` will not survive a relaunch.
        let isPersistent: Bool
    }

    private static let keyTag = "jp.co.pendako.siop.key"

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var identity: Identity?

    private var op: SelfIssuedOP?

    /// Opening a redirect completes asynchronously. Anything that moves on from
    /// the request in flight bumps this, so a completion that lands afterwards
    /// cannot overwrite whatever replaced it.
    private var requestGeneration = 0

    init() {
        do {
            let (provider, isPersistent) = try Self.makeKeyProvider()
            let op = SelfIssuedOP(keyProvider: provider)
            let jwk = try provider.publicJWK()
            self.op = op
            identity = Identity(subject: jwk.thumbprint(), jwk: jwk, isPersistent: isPersistent)
        } catch {
            phase = .failed("鍵を準備できませんでした: \(Self.describe(error))")
        }
    }

    /// Prefers a Keychain-backed key so `sub` stays stable across launches,
    /// falling back to an ephemeral one so the app remains usable.
    private static func makeKeyProvider() throws -> (SIOPKeyProvider, Bool) {
        do {
            return (try SecKeyProvider.loadOrCreate(tag: keyTag), true)
        } catch {
            return (try SecKeyProvider.generate(), false)
        }
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

        open(redirectURL) { [weak self] opened in
            guard let self, generation == self.requestGeneration else { return }
            self.phase = opened
                ? onSuccess(clientID, redirectURL)
                : .undeliverable(clientID: clientID, redirectURL: redirectURL)
        }
    }

    private func open(_ url: URL, completion: @escaping (Bool) -> Void) {
#if DEBUG
        // UI tests use this to hold a delivery open while another request
        // arrives, which is the race the generation check exists for.
        if let delay = Self.deliveryDelayForTesting {
            UIApplication.shared.open(url) { opened in
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { completion(opened) }
            }
            return
        }
#endif
        UIApplication.shared.open(url, completionHandler: completion)
    }

#if DEBUG
    static let deliveryDelayLaunchArgument = "-siopDeliveryDelaySeconds"

    private static var deliveryDelayForTesting: TimeInterval? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: deliveryDelayLaunchArgument),
              arguments.index(after: flag) < arguments.endIndex,
              let seconds = TimeInterval(arguments[arguments.index(after: flag)])
        else { return nil }
        return seconds
    }
#endif

    func reset() {
        requestGeneration += 1
        phase = identity == nil ? phase : .idle
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
