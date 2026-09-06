import Security
import XCTest
@testable import SIOPKit

final class Base64URLTests: XCTestCase {
    func testEncodeUsesURLSafeAlphabetWithoutPadding() {
        // base64: "+/++AA==" -> base64url: "-_--AA"
        XCTAssertEqual(Base64URL.encode(Data([251, 255, 190, 0])), "-_--AA")
    }

    func testDecodeRestoresPadding() {
        XCTAssertEqual(Base64URL.decode("-_--AA"), Data([251, 255, 190, 0]))
    }
}

final class ThumbprintTests: XCTestCase {
    // Test vector from RFC 7638 Section 3.1.
    func testRFC7638ExampleThumbprint() {
        let jwk = RSAPublicJWK(
            n: "0vx7agoebGcQSuuPiLJXZptN9nndrQmbXEps2aiAFbWhM78LhWx4cbbfAAtVT86zwu1RK7aPFFxuhDR1L6tSoc_BJECPebWKRXjBZCiFV4n3oknjhMstn64tZ_2W-5JsGY4Hc5n9yBXArwl93lqt7_RN5w6Cf0h4QyQ5v-65YGjQR0_FDW2QvzqY368QQMicAtaSqzs8KJZgnYb9c7d0zgdAZHzu6qMQvRL5hajrn1n91CbOpbISD08qNLyrdkt-bFTWhAI4vMQFh6WeZu0fM4lFd2NcRwr3XPksINHaQ-G_xBniIqbw0Ls1jF44-csFCur-kEgU8awapJzKnqDKgw",
            e: "AQAB"
        )
        XCTAssertEqual(jwk.thumbprint(), "NzbLsXh8uDCcd-6MNwXF4W_7noWXFZAfHkxZsRGC9Xs")
    }
}

final class AuthorizationRequestTests: XCTestCase {
    func testParsesValidRequest() throws {
        let url = URL(string: "openid://?response_type=id_token&client_id=https%3A%2F%2Fclient.example.org%2Fcb&scope=openid%20profile&state=af0ifjsldkj&nonce=n-0S6_WzA2Mj")!
        let request = try AuthorizationRequest(url: url)
        XCTAssertEqual(request.responseType, "id_token")
        XCTAssertEqual(request.scope, ["openid", "profile"])
        XCTAssertEqual(request.clientID, "https://client.example.org/cb")
        XCTAssertEqual(request.nonce, "n-0S6_WzA2Mj")
        XCTAssertEqual(request.state, "af0ifjsldkj")
    }

    func testRejectsScopeWithoutOpenID() {
        let url = URL(string: "openid://?response_type=id_token&client_id=https%3A%2F%2Fc.example%2Fcb&scope=profile&nonce=n1")!
        XCTAssertThrowsError(try AuthorizationRequest(url: url)) { error in
            XCTAssertEqual(error as? SIOPError, .invalidScope)
        }
    }

    func testRejectsUnsupportedResponseType() {
        let url = URL(string: "openid://?response_type=code&client_id=https%3A%2F%2Fc.example%2Fcb&scope=openid&nonce=n1")!
        XCTAssertThrowsError(try AuthorizationRequest(url: url)) { error in
            XCTAssertEqual(error as? SIOPError, .unsupportedResponseType("code"))
        }
    }

    func testRejectsMissingNonce() {
        let url = URL(string: "openid://?response_type=id_token&client_id=https%3A%2F%2Fc.example%2Fcb&scope=openid")!
        XCTAssertThrowsError(try AuthorizationRequest(url: url))
    }

    func testRejectsMissingClientID() {
        let url = URL(string: "openid://?response_type=id_token&scope=openid&nonce=n1")!
        XCTAssertThrowsError(try AuthorizationRequest(url: url))
    }

    func testRejectsMismatchedRedirectURI() {
        let url = URL(string: "openid://?response_type=id_token&client_id=https%3A%2F%2Fc.example%2Fcb&redirect_uri=https%3A%2F%2Fevil.example%2Fcb&scope=openid&nonce=n1")!
        XCTAssertThrowsError(try AuthorizationRequest(url: url))
    }
}

final class KeyAndDERTests: XCTestCase {
    func testJWKRoundTripThroughDER() throws {
        let provider = try SecKeyProvider.generate()
        let jwk = try provider.publicJWK()
        XCTAssertEqual(jwk.e, "AQAB")

        let message = Data("hello".utf8)
        let signature = try provider.sign(message)
        var error: Unmanaged<CFError>?
        XCTAssertTrue(SecKeyVerifySignature(
            try jwk.secKey(), .rsaSignatureMessagePKCS1v15SHA256,
            message as CFData, signature as CFData, &error
        ))
    }
}

final class SelfIssuedOPTests: XCTestCase {
    private static let keyProvider = try! SecKeyProvider.generate()

    private var requestURL: URL {
        URL(string: "openid://?response_type=id_token&client_id=https%3A%2F%2Fclient.example.org%2Fcb&scope=openid%20profile&state=af0ifjsldkj&nonce=n-0S6_WzA2Mj")!
    }

    func testIssuesValidatableIDToken() throws {
        let op = SelfIssuedOP(keyProvider: Self.keyProvider)
        let response = try op.handle(url: requestURL)

        XCTAssertEqual(response.state, "af0ifjsldkj")
        XCTAssertTrue(response.redirectURL.absoluteString.hasPrefix("https://client.example.org/cb#id_token="))
        XCTAssertTrue(response.redirectURL.absoluteString.hasSuffix("&state=af0ifjsldkj"))

        let payload = try SelfIssuedIDTokenValidator.validate(
            idToken: response.idToken,
            expectedAudience: "https://client.example.org/cb",
            expectedNonce: "n-0S6_WzA2Mj"
        )
        XCTAssertEqual(payload["iss"] as? String, "https://self-issued.me")
        XCTAssertEqual(payload["aud"] as? String, "https://client.example.org/cb")
    }

    func testSubEqualsSubJWKThumbprint() throws {
        let op = SelfIssuedOP(keyProvider: Self.keyProvider)
        let response = try op.handle(url: requestURL)
        let (_, payload, _, _) = try JWS.decode(response.idToken)
        let subJWK = try XCTUnwrap(payload["sub_jwk"] as? [String: Any])
        let jwk = RSAPublicJWK(
            n: try XCTUnwrap(subJWK["n"] as? String),
            e: try XCTUnwrap(subJWK["e"] as? String)
        )
        XCTAssertEqual(payload["sub"] as? String, jwk.thumbprint())
        XCTAssertEqual(jwk, try Self.keyProvider.publicJWK())
    }

    func testTamperedPayloadFailsSignatureCheck() throws {
        let op = SelfIssuedOP(keyProvider: Self.keyProvider)
        let response = try op.handle(url: requestURL)

        var parts = response.idToken.components(separatedBy: ".")
        let payloadData = try XCTUnwrap(Base64URL.decode(parts[1]))
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: payloadData) as? [String: Any])
        payload["aud"] = "https://attacker.example/cb"
        parts[1] = Base64URL.encode(try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]))
        let tampered = parts.joined(separator: ".")

        XCTAssertThrowsError(try SelfIssuedIDTokenValidator.validate(
            idToken: tampered,
            expectedAudience: "https://attacker.example/cb"
        )) { error in
            XCTAssertEqual(error as? SIOPError, .invalidToken("signature verification failed"))
        }
    }

    func testExpiredTokenFailsValidation() throws {
        let op = SelfIssuedOP(keyProvider: Self.keyProvider)
        let response = try op.handle(url: requestURL, now: Date(timeIntervalSinceNow: -3600))
        XCTAssertThrowsError(try SelfIssuedIDTokenValidator.validate(
            idToken: response.idToken,
            expectedAudience: "https://client.example.org/cb"
        )) { error in
            XCTAssertEqual(error as? SIOPError, .invalidToken("token expired"))
        }
    }
}

final class ErrorResponseTests: XCTestCase {
    private var request: AuthorizationRequest {
        get throws {
            try AuthorizationRequest(url: URL(string: "openid://?response_type=id_token&client_id=https%3A%2F%2Fclient.example.org%2Fcb&scope=openid&state=a%20b&nonce=n1")!)
        }
    }

    func testDeniedRequestBuildsErrorRedirect() throws {
        let response = try AuthenticationErrorResponse(request: try request)
        XCTAssertEqual(
            response.redirectURL.absoluteString,
            "https://client.example.org/cb#error=access_denied&state=a%20b"
        )
    }

    func testErrorDescriptionIsEncoded() throws {
        let response = try AuthenticationErrorResponse(
            error: "invalid_request",
            errorDescription: "nonce is required",
            request: try request
        )
        XCTAssertEqual(
            response.redirectURL.absoluteString,
            "https://client.example.org/cb#error=invalid_request&error_description=nonce%20is%20required&state=a%20b"
        )
    }
}

final class MetadataTests: XCTestCase {
    /// Advertising a capability that is not implemented sends RPs down a path
    /// that always fails, so the two are held together here.
    func testAdvertisesOnlyWhatIsImplemented() {
        let configuration = SelfIssuedMetadata.configuration

        XCTAssertEqual(configuration["issuer"] as? String, SelfIssuedIDToken.issuer)
        XCTAssertEqual(configuration["authorization_endpoint"] as? String, "openid:")
        XCTAssertEqual(configuration["response_types_supported"] as? [String], ["id_token"])
        XCTAssertEqual(configuration["id_token_signing_alg_values_supported"] as? [String], ["RS256"])

        // request / request_uri are not handled. request_uri_parameter_supported
        // defaults to true when omitted, so it has to be present and false.
        XCTAssertNil(configuration["request_object_signing_alg_values_supported"])
        XCTAssertEqual(configuration["request_parameter_supported"] as? Bool, false)
        XCTAssertEqual(configuration["request_uri_parameter_supported"] as? Bool, false)
    }
}
