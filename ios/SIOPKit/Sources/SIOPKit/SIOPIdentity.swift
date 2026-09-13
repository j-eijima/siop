import Foundation
import Security

/// A key the user holds for one Relying Party, with the names they gave it.
///
/// The subject an RP sees is the thumbprint of the key that signs for it, so an
/// identity is really a key. It belongs to exactly one RP: answering a second
/// RP with it would hand both the same subject and let them discover they are
/// talking to the same person. One RP may have several — the user can answer
/// it as more than one person — but no identity ever answers two.
public struct SIOPIdentity: Identifiable, Equatable, Codable {
    public let id: String
    /// The RP this identity answers. Section 7.2: its redirect URI.
    public let clientID: String
    /// Names for the user's own benefit. Never sent to the RP.
    public fileprivate(set) var label: String
    public fileprivate(set) var note: String
    public let createdAt: Date
    public fileprivate(set) var lastUsedAt: Date?
    /// Where the private key lives. Not the subject, which comes from the key itself.
    let keyTag: String

    /// The order an RP's identities are offered in. The one used most recently
    /// comes first, being the one the user answered as last time; identities
    /// never used follow, oldest first.
    public static func preferred(_ a: SIOPIdentity, _ b: SIOPIdentity) -> Bool {
        switch (a.lastUsedAt, b.lastUsedAt) {
        case let (x?, y?): return x > y
        case (.some, nil): return true
        case (nil, .some): return false
        case (nil, nil): return a.createdAt < b.createdAt
        }
    }
}

/// Where identity records — names, and which RP each answers — are kept.
public protocol SIOPIdentityRecords {
    func loadAll() throws -> [SIOPIdentity]
    func save(_ identity: SIOPIdentity) throws
    func remove(id: String) throws
}

/// Where private keys are kept, by tag.
public protocol SIOPIdentityKeys {
    func key(tag: String) throws -> SIOPKeyProvider?
    func createKey(tag: String) throws -> SIOPKeyProvider
    func removeKey(tag: String) throws
}

/// The identities on this device, and the keys behind them.
public final class SIOPIdentityStore {
    private let records: SIOPIdentityRecords
    private let keys: SIOPIdentityKeys
    private let tagPrefix: String
    private let adoptsPerRPKeys: Bool
    private let now: () -> Date

    /// - Parameter adoptsPerRPKeys: Whether keys made by `KeychainKeyStore`
    ///   under the same `tagPrefix` are taken over as identities. Devices that
    ///   ran the key-per-RP version hold one for every RP they answered, and
    ///   those RPs already know the subject it produces.
    public init(
        records: SIOPIdentityRecords,
        keys: SIOPIdentityKeys,
        tagPrefix: String,
        adoptsPerRPKeys: Bool = false,
        now: @escaping () -> Date = Date.init
    ) {
        self.records = records
        self.keys = keys
        self.tagPrefix = tagPrefix
        self.adoptsPerRPKeys = adoptsPerRPKeys
        self.now = now
    }

    /// Identities and keys in the Keychain, so they survive relaunches.
    public static func keychain(tagPrefix: String) -> SIOPIdentityStore {
        SIOPIdentityStore(
            records: KeychainIdentityRecords(service: "\(tagPrefix).identities"),
            keys: KeychainIdentityKeys(),
            tagPrefix: tagPrefix,
            adoptsPerRPKeys: true
        )
    }

    /// Identities and keys in memory only. For tests and tools, where nothing
    /// should outlive the process.
    public static func ephemeral() -> SIOPIdentityStore {
        SIOPIdentityStore(records: InMemoryIdentityRecords(), keys: InMemoryIdentityKeys(), tagPrefix: "ephemeral")
    }

    public func allIdentities() throws -> [SIOPIdentity] {
        try records.loadAll().sorted(by: SIOPIdentity.preferred)
    }

    /// The identities held for `clientID`, in the order they should be offered.
    ///
    /// Creates no key, so it is safe to call as soon as a request arrives. It
    /// may write a record, when a key from the key-per-RP version is found for
    /// this RP and taken over.
    public func identities(for clientID: String) throws -> [SIOPIdentity] {
        var held = try records.loadAll().filter { $0.clientID == clientID }
        if adoptsPerRPKeys, let adopted = try adoptPerRPKey(for: clientID, among: held) {
            held.append(adopted)
        }
        return held.sorted(by: SIOPIdentity.preferred)
    }

    /// Generates a key for `clientID`.
    ///
    /// That costs an RSA generation and a permanent keystore entry, and
    /// `client_id` is chosen by whoever sent the request. Call it only on the
    /// user's explicit request — never because a request arrived.
    public func createIdentity(for clientID: String, label: String = "", note: String = "") throws -> SIOPIdentity {
        let tag = "\(tagPrefix).\(UUID().uuidString)"
        _ = try keys.createKey(tag: tag)
        let identity = SIOPIdentity(
            id: UUID().uuidString,
            clientID: clientID,
            label: label,
            note: note,
            createdAt: now(),
            lastUsedAt: nil,
            keyTag: tag
        )
        do {
            try records.save(identity)
        } catch {
            try? keys.removeKey(tag: tag)
            throw error
        }
        return identity
    }

    /// Changes the names and nothing else. The key, and so the subject, cannot
    /// be edited: a different key would be a different identity.
    public func relabel(_ identity: SIOPIdentity, label: String, note: String) throws -> SIOPIdentity {
        var updated = identity
        updated.label = label
        updated.note = note
        try records.save(updated)
        return updated
    }

    /// Records that the identity has just answered its RP, which puts it first
    /// the next time that RP asks.
    @discardableResult
    public func markUsed(_ identity: SIOPIdentity) throws -> SIOPIdentity {
        var updated = identity
        updated.lastUsedAt = now()
        try records.save(updated)
        return updated
    }

    /// Removes the key along with the record. Nothing can sign as this subject
    /// again unless the key is restored from a backup; the account the RP holds
    /// for it is untouched, since this device has no way to reach it.
    public func delete(_ identity: SIOPIdentity) throws {
        try keys.removeKey(tag: identity.keyTag)
        try records.remove(id: identity.id)
    }

    public func keyProvider(for identity: SIOPIdentity) throws -> SIOPKeyProvider {
        guard let key = try keys.key(tag: identity.keyTag) else {
            throw SIOPError.invalidKey
        }
        return key
    }

    public func publicJWK(of identity: SIOPIdentity) throws -> RSAPublicJWK {
        try keyProvider(for: identity).publicJWK()
    }

    /// A key-per-RP key exists only because the user once answered this RP, so
    /// it is marked used. Takes it over at most once, and creates nothing when
    /// there is no such key.
    private func adoptPerRPKey(for clientID: String, among held: [SIOPIdentity]) throws -> SIOPIdentity? {
        let tag = KeychainKeyStore.tag(prefix: tagPrefix, clientID: clientID)
        guard !held.contains(where: { $0.keyTag == tag }), try keys.key(tag: tag) != nil else {
            return nil
        }
        let adopted = SIOPIdentity(
            id: UUID().uuidString,
            clientID: clientID,
            label: "",
            note: "",
            createdAt: now(),
            lastUsedAt: now(),
            keyTag: tag
        )
        try records.save(adopted)
        return adopted
    }
}

// MARK: - Keychain

/// Private keys in the Keychain, permanent and tagged.
public struct KeychainIdentityKeys: SIOPIdentityKeys {
    public init() {}

    public func key(tag: String) throws -> SIOPKeyProvider? {
        try SecKeyProvider.load(tag: tag)
    }

    public func createKey(tag: String) throws -> SIOPKeyProvider {
        try SecKeyProvider.create(tag: tag)
    }

    public func removeKey(tag: String) throws {
        try SecKeyProvider.delete(tag: tag)
    }
}

/// Identity records as generic-password items, one per identity.
///
/// Kept in the Keychain rather than in user defaults so that they live and die
/// with the keys they describe: defaults are wiped when the app is removed,
/// Keychain items are not, and a key without its record would be unreachable.
public struct KeychainIdentityRecords: SIOPIdentityRecords {
    public let service: String

    public init(service: String) {
        self.service = service
    }

    public func loadAll() throws -> [SIOPIdentity] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnData as String: true,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let items = result as? [Data] else {
            throw SIOPError.keyStore(status)
        }
        let decoder = JSONDecoder()
        return items.compactMap { try? decoder.decode(SIOPIdentity.self, from: $0) }
    }

    public func save(_ identity: SIOPIdentity) throws {
        let data = try JSONEncoder().encode(identity)
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: identity.id,
        ]
        let updated = SecItemUpdate(item as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw SIOPError.keyStore(updated) }

        var added = item
        added[kSecValueData as String] = data
        let status = SecItemAdd(added as CFDictionary, nil)
        guard status == errSecSuccess else { throw SIOPError.keyStore(status) }
    }

    public func remove(id: String) throws {
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id,
        ]
        let status = SecItemDelete(item as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SIOPError.keyStore(status)
        }
    }
}

// MARK: - In memory

public final class InMemoryIdentityRecords: SIOPIdentityRecords {
    private var byID: [String: SIOPIdentity] = [:]

    public init() {}

    public func loadAll() throws -> [SIOPIdentity] { Array(byID.values) }
    public func save(_ identity: SIOPIdentity) throws { byID[identity.id] = identity }
    public func remove(id: String) throws { byID[id] = nil }
}

public final class InMemoryIdentityKeys: SIOPIdentityKeys {
    private var byTag: [String: SIOPKeyProvider] = [:]

    public init() {}

    public func key(tag: String) throws -> SIOPKeyProvider? { byTag[tag] }

    public func createKey(tag: String) throws -> SIOPKeyProvider {
        let key = try SecKeyProvider.generate()
        byTag[tag] = key
        return key
    }

    public func removeKey(tag: String) throws { byTag[tag] = nil }
}
