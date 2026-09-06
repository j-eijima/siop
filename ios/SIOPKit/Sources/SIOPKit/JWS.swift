import Foundation

/// Minimal JWS (RFC 7515) compact serialization with RS256, the mandatory
/// signing algorithm for Self-Issued OPs (OpenID Connect Core 1.0 Section 7.1).
enum JWS {
    static func signRS256(payload: [String: Any], key: SIOPKeyProvider) throws -> String {
        let header = try encodeSegment(["alg": "RS256", "typ": "JWT"])
        let body = try encodeSegment(payload)
        let signingInput = "\(header).\(body)"
        let signature = try key.sign(Data(signingInput.utf8))
        return "\(signingInput).\(Base64URL.encode(signature))"
    }

    static func decode(
        _ jwt: String
    ) throws -> (header: [String: Any], payload: [String: Any], signature: Data, signingInput: Data) {
        let parts = jwt.components(separatedBy: ".")
        guard parts.count == 3,
              let headerData = Base64URL.decode(parts[0]),
              let payloadData = Base64URL.decode(parts[1]),
              let signature = Base64URL.decode(parts[2]),
              let header = (try? JSONSerialization.jsonObject(with: headerData)) as? [String: Any],
              let payload = (try? JSONSerialization.jsonObject(with: payloadData)) as? [String: Any]
        else {
            throw SIOPError.invalidToken("malformed JWT")
        }
        return (header, payload, signature, Data("\(parts[0]).\(parts[1])".utf8))
    }

    private static func encodeSegment(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return Base64URL.encode(data)
    }
}
