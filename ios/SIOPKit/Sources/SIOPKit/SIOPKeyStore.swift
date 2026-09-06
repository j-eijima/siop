import CryptoKit
import Foundation

/// Resolves the key that identifies this device to one particular RP.
///
/// A Self-Issued OP advertises `subject_types_supported: ["pairwise"]`, and the
/// subject is the thumbprint of the key that signed the token. Presenting one
/// key to everyone would therefore hand every RP the same identifier, letting
/// any two of them discover they are talking to the same person. A separate key
/// per RP is what makes the advertised pairwise subject true.
public protocol SIOPKeyStore {
    /// The same `clientID` must return the same key every time, so that a user
    /// returning to an RP is recognised as the same subject. Creates one on
    /// first use, so only call it once the user has agreed to answer this RP.
    func keyProvider(for clientID: String) throws -> SIOPKeyProvider

    /// The key already held for `clientID`, or nil if none has been made yet.
    ///
    /// Creating a key costs an RSA generation and a permanent keystore entry,
    /// and `client_id` is chosen by whoever sent the request. Anything that
    /// runs before the user has agreed — showing a consent screen, say — must
    /// go through here, or a stream of unanswered requests would fill the
    /// keystore and stall on key generation.
    func existingKeyProvider(for clientID: String) throws -> SIOPKeyProvider?
}

public extension SIOPKeyStore {
    /// The identifier this device presents to `clientID`, creating the key if
    /// this RP has not been answered before.
    func subject(for clientID: String) throws -> String {
        try keyProvider(for: clientID).publicJWK().thumbprint()
    }

    /// The identifier already established with `clientID`, or nil if this RP
    /// has never been answered. Creates nothing.
    func existingSubject(for clientID: String) throws -> String? {
        try existingKeyProvider(for: clientID)?.publicJWK().thumbprint()
    }
}

/// Keys held in the Keychain, one per RP, so subjects survive relaunches.
public struct KeychainKeyStore: SIOPKeyStore {
    public let tagPrefix: String

    public init(tagPrefix: String) {
        self.tagPrefix = tagPrefix
    }

    public func keyProvider(for clientID: String) throws -> SIOPKeyProvider {
        try SecKeyProvider.loadOrCreate(tag: Self.tag(prefix: tagPrefix, clientID: clientID))
    }

    public func existingKeyProvider(for clientID: String) throws -> SIOPKeyProvider? {
        try SecKeyProvider.load(tag: Self.tag(prefix: tagPrefix, clientID: clientID))
    }

    /// SIOP has no registration, so the `client_id` — the RP's redirect URI —
    /// is the only stable name an RP has. It is hashed rather than embedded so
    /// that the tag is a fixed size and free of URI punctuation.
    static func tag(prefix: String, clientID: String) -> String {
        let digest = SHA256.hash(data: Data(clientID.utf8))
        return "\(prefix).\(Base64URL.encode(Data(digest)))"
    }
}

/// Keys kept in memory only, one per RP. For tests and tools, where nothing
/// should outlive the process.
public final class EphemeralKeyStore: SIOPKeyStore {
    private var providers: [String: SIOPKeyProvider] = [:]

    public init() {}

    public func keyProvider(for clientID: String) throws -> SIOPKeyProvider {
        if let existing = providers[clientID] { return existing }
        let created = try SecKeyProvider.generate()
        providers[clientID] = created
        return created
    }

    public func existingKeyProvider(for clientID: String) throws -> SIOPKeyProvider? {
        providers[clientID]
    }
}
