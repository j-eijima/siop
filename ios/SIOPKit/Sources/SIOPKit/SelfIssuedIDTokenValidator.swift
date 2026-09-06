import Foundation
import Security

/// RP-side validation of a self-issued ID Token (OpenID Connect Core 1.0 Section 7.5).
public enum SelfIssuedIDTokenValidator {
    @discardableResult
    public static func validate(
        idToken: String,
        expectedAudience: String,
        expectedNonce: String? = nil,
        now: Date = Date()
    ) throws -> [String: Any] {
        let (header, payload, signature, signingInput) = try JWS.decode(idToken)

        guard header["alg"] as? String == "RS256" else {
            throw SIOPError.invalidToken("unsupported alg")
        }
        // 7.5 rule 2: iss must be https://self-issued.me.
        guard payload["iss"] as? String == SelfIssuedIDToken.issuer else {
            throw SIOPError.invalidToken("iss must be \(SelfIssuedIDToken.issuer)")
        }
        // 7.5 rule 3: sub_jwk must be present.
        guard let subJWK = payload["sub_jwk"] as? [String: Any],
              subJWK["kty"] as? String == "RSA",
              let n = subJWK["n"] as? String,
              let e = subJWK["e"] as? String
        else {
            throw SIOPError.invalidToken("sub_jwk missing or not an RSA key")
        }
        let jwk = RSAPublicJWK(n: n, e: e)
        // 7.5 rule 4: sub must equal the thumbprint of sub_jwk.
        guard payload["sub"] as? String == jwk.thumbprint() else {
            throw SIOPError.invalidToken("sub does not match sub_jwk thumbprint")
        }

        let audMatches: Bool
        switch payload["aud"] {
        case let aud as String: audMatches = aud == expectedAudience
        case let aud as [String]: audMatches = aud.contains(expectedAudience)
        default: audMatches = false
        }
        guard audMatches else {
            throw SIOPError.invalidToken("aud mismatch")
        }

        if let expectedNonce {
            guard payload["nonce"] as? String == expectedNonce else {
                throw SIOPError.invalidToken("nonce mismatch")
            }
        }
        guard let exp = payload["exp"] as? TimeInterval, now.timeIntervalSince1970 < exp else {
            throw SIOPError.invalidToken("token expired")
        }

        // 7.5 rule 5: verify the signature with the key in sub_jwk.
        let publicKey = try jwk.secKey()
        var error: Unmanaged<CFError>?
        guard SecKeyVerifySignature(
            publicKey, .rsaSignatureMessagePKCS1v15SHA256,
            signingInput as CFData, signature as CFData, &error
        ) else {
            throw SIOPError.invalidToken("signature verification failed")
        }
        return payload
    }
}
