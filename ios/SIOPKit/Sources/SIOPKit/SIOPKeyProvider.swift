import Foundation
import Security

/// Abstraction over the OP's key pair: RS256 signing and the public key as a JWK.
public protocol SIOPKeyProvider {
    func publicJWK() throws -> RSAPublicJWK
    func sign(_ data: Data) throws -> Data
}

/// Key provider backed by a Security-framework RSA key pair.
public final class SecKeyProvider: SIOPKeyProvider {
    public let privateKey: SecKey
    public let publicKey: SecKey

    public init(privateKey: SecKey) throws {
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw SIOPError.invalidKey
        }
        self.privateKey = privateKey
        self.publicKey = publicKey
    }

    /// Generates an ephemeral (non-persisted) RSA key pair.
    public static func generate(bits: Int = 2048) throws -> SecKeyProvider {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: bits,
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw SIOPError.keyGenerationFailed(describe(error))
        }
        return try SecKeyProvider(privateKey: key)
    }

    /// The key stored under `tag`, or nil when there is none. Creates nothing.
    public static func load(tag: String) throws -> SecKeyProvider? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: Data(tag.utf8),
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecReturnRef as String: true,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let item {
            return try SecKeyProvider(privateKey: item as! SecKey)
        }
        guard status == errSecItemNotFound else {
            throw SIOPError.keyGenerationFailed("keychain error \(status)")
        }
        return nil
    }

    /// Loads the key pair stored under `tag` in the Keychain, generating and
    /// persisting one on first use. Persisting the key keeps `sub` stable
    /// across authentications from the same device.
    public static func loadOrCreate(tag: String) throws -> SecKeyProvider {
        if let existing = try load(tag: tag) { return existing }
        let tagData = Data(tag.utf8)
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: tagData,
            ],
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw SIOPError.keyGenerationFailed(describe(error))
        }
        return try SecKeyProvider(privateKey: key)
    }

    public func publicJWK() throws -> RSAPublicJWK {
        var error: Unmanaged<CFError>?
        guard let der = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw SIOPError.invalidKey
        }
        let (n, e) = try DER.parseRSAPublicKey(der)
        return RSAPublicJWK(n: Base64URL.encode(n), e: Base64URL.encode(e))
    }

    public func sign(_ data: Data) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey, .rsaSignatureMessagePKCS1v15SHA256, data as CFData, &error
        ) as Data? else {
            throw SIOPError.signingFailed(Self.describe(error))
        }
        return signature
    }

    private static func describe(_ error: Unmanaged<CFError>?) -> String? {
        error.map { String(describing: $0.takeRetainedValue()) }
    }
}
