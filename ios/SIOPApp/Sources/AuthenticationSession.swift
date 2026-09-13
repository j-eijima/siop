import SIOPKit
import SwiftUI
import UIKit

/// Drives one authentication request through consent to the response
/// delivered back to the RP (OpenID Connect Core 1.0 Section 7.3-7.4), and
/// keeps the identities the user answers as.
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

    /// Shared with the key-per-RP version, so that the keys it made for each
    /// RP are found and taken over as identities.
    private static let tagPrefix = "jp.co.pendako.siop.key"

    /// False when the Keychain was unavailable and identities live in memory,
    /// which means they will not survive a relaunch.
    let isPersistent: Bool

    @Published private(set) var phase: Phase = .idle
    /// Every identity on the device, in the order they are offered.
    @Published private(set) var identities: [SIOPIdentity] = []
    /// The public key of each identity whose key could be read. An identity
    /// missing from here is still listed, but cannot answer.
    @Published private(set) var publicKeys: [SIOPIdentity.ID: RSAPublicJWK] = [:]
    /// An identity operation that failed, to be shown and then cleared.
    @Published var problem: String?

    private let store: SIOPIdentityStore
    private let openURL: (URL, @escaping (Bool) -> Void) -> Void

    /// Opening a redirect completes asynchronously. Anything that moves on from
    /// the request in flight bumps this, so a completion that lands afterwards
    /// cannot overwrite whatever replaced it.
    private var requestGeneration = 0

    /// `open` delivers the response to the RP, reporting whether anything
    /// could handle the URL. Injected so the delivery race can be tested
    /// without a real redirect.
    init(
        store: SIOPIdentityStore? = nil,
        open: @escaping (URL, @escaping (Bool) -> Void) -> Void = { url, completion in
            UIApplication.shared.open(url, completionHandler: completion)
        }
    ) {
        openURL = open
        if let store {
            self.store = store
            isPersistent = false
        } else {
            let (made, persistent) = Self.makeStore()
            self.store = made
            isPersistent = persistent
        }
        refresh()
    }

    /// Prefers the Keychain so identities survive relaunches, falling back to
    /// memory so the app remains usable. The Keychain is proven by reading
    /// from it, which creates nothing.
    private static func makeStore() -> (SIOPIdentityStore, Bool) {
        let keychain = SIOPIdentityStore.keychain(tagPrefix: tagPrefix)
        do {
            _ = try keychain.allIdentities()
            return (keychain, true)
        } catch {
            return (.ephemeral(), false)
        }
    }

    // MARK: - Identities

    /// The identities that may answer `clientID`, in the order to offer them.
    func identities(for clientID: String) -> [SIOPIdentity] {
        identities.filter { $0.clientID == clientID }
    }

    func subject(of identity: SIOPIdentity) -> String? {
        publicKeys[identity.id]?.thumbprint()
    }

    /// Makes a key, so only ever at the user's explicit request.
    @discardableResult
    func createIdentity(for clientID: String, label: String, note: String) -> SIOPIdentity? {
        do {
            let created = try store.createIdentity(for: clientID, label: label, note: note)
            refresh()
            return created
        } catch {
            problem = String(localized: "Could not create the identity: \(Self.describe(error))")
            return nil
        }
    }

    func relabel(_ identity: SIOPIdentity, label: String, note: String) {
        let current = identities.first { $0.id == identity.id } ?? identity
        do {
            _ = try store.relabel(current, label: label, note: note)
            refresh()
        } catch {
            problem = String(localized: "Could not save: \(Self.describe(error))")
        }
    }

    func delete(_ identity: SIOPIdentity) {
        do {
            try store.delete(identity)
            refresh()
        } catch {
            problem = String(localized: "Could not delete: \(Self.describe(error))")
        }
    }

    private func refresh() {
        do {
            identities = try store.allIdentities()
        } catch {
            problem = String(localized: "Could not load identities: \(Self.describe(error))")
        }
        var keys: [SIOPIdentity.ID: RSAPublicJWK] = [:]
        for identity in identities {
            keys[identity.id] = try? store.publicJWK(of: identity)
        }
        publicKeys = keys
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
            let request = try AuthorizationRequest(url: url)
            // Takes over the key the key-per-RP version made for this RP, if
            // there is one, so it is offered. Creates no key: nobody has
            // answered anything yet.
            _ = try? store.identities(for: request.clientID)
            refresh()
            phase = .consent(request)
        } catch {
            phase = .failed(Self.describe(error))
        }
    }

    /// Signs as `identity`, or — when there is none to sign as — as a new
    /// identity for this RP, made now because the user has just said to
    /// answer (docs/decisions/0004).
    func approve(_ request: AuthorizationRequest, as identity: SIOPIdentity?) {
        if let identity, identity.clientID != request.clientID {
            // Two RPs answered by one identity would be handed one subject.
            phase = .failed(String(localized: "This identity answers only \(identity.clientID). It cannot answer another RP."))
            return
        }
        do {
            let signer = try identity ?? store.createIdentity(for: request.clientID)
            let response = try SelfIssuedOP.respond(to: request, signingWith: try store.keyProvider(for: signer))
            _ = try? store.markUsed(signer)
            refresh()
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

    /// Shown to the user, so translated. The reasons SIOPKit gives are
    /// protocol detail — "nonce is required" — and stay as they are.
    private static func describe(_ error: Error) -> String {
        guard let error = error as? SIOPError else {
            return String(describing: error)
        }
        switch error {
        case let .invalidRequest(reason): return String(localized: "Invalid request: \(reason)")
        case let .unsupportedResponseType(type): return String(localized: "Unsupported response_type: \(type)")
        case .invalidScope: return String(localized: "scope does not include openid")
        case let .keyGenerationFailed(reason):
            return String(localized: "Key generation failed: \(reason ?? String(localized: "unknown"))")
        case let .signingFailed(reason):
            return String(localized: "Signing failed: \(reason ?? String(localized: "unknown"))")
        case .derParsingFailed: return String(localized: "Could not parse the key")
        case .invalidKey: return String(localized: "Could not read the key")
        case let .invalidToken(reason): return String(localized: "Invalid ID Token: \(reason)")
        case let .keyStore(status): return String(localized: "Keychain unavailable (OSStatus \(Int(status)))")
        }
    }
}
