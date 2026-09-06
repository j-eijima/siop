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
        case sent(clientID: String, redirectURL: URL)
        case declined(clientID: String)
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

    func receive(_ url: URL) {
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
            phase = .sent(clientID: request.clientID, redirectURL: response.redirectURL)
            UIApplication.shared.open(response.redirectURL)
        } catch {
            phase = .failed(Self.describe(error))
        }
    }

    /// Section 3.1.2.6: tell the RP the user declined rather than leaving it hanging.
    func decline(_ request: AuthorizationRequest) {
        phase = .declined(clientID: request.clientID)
        if let response = try? AuthenticationErrorResponse(request: request) {
            UIApplication.shared.open(response.redirectURL)
        }
    }

    func reset() {
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
