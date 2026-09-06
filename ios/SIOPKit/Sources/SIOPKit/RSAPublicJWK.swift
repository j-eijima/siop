import CryptoKit
import Foundation
import Security

/// RSA public key as a JWK (RFC 7517), as embedded in the `sub_jwk` claim.
public struct RSAPublicJWK: Equatable {
    public let n: String
    public let e: String
    public var kty: String { "RSA" }

    public init(n: String, e: String) {
        self.n = n
        self.e = e
    }

    public var jsonObject: [String: String] {
        ["kty": kty, "n": n, "e": e]
    }

    /// RFC 7638 JWK thumbprint (SHA-256, base64url) — used as the `sub` claim
    /// value of a self-issued ID Token (OpenID Connect Core 1.0 Section 7.4).
    public func thumbprint() -> String {
        let canonical = "{\"e\":\"\(e)\",\"kty\":\"\(kty)\",\"n\":\"\(n)\"}"
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return Base64URL.encode(Data(digest))
    }

    /// Reconstructs a Security-framework public key, e.g. for signature verification.
    public func secKey() throws -> SecKey {
        guard let nData = Base64URL.decode(n), let eData = Base64URL.decode(e) else {
            throw SIOPError.invalidKey
        }
        let der = DER.encodeRSAPublicKey(n: nData, e: eData)
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(der as CFData, attributes as CFDictionary, &error) else {
            throw SIOPError.invalidKey
        }
        return key
    }
}
