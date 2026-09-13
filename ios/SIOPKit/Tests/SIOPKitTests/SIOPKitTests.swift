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

final class PairwiseSubjectTests: XCTestCase {
    private let store = EphemeralKeyStore()

    private func request(clientID: String) throws -> AuthorizationRequest {
        let encoded = clientID.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        return try AuthorizationRequest(
            url: URL(string: "openid://?response_type=id_token&scope=openid&nonce=n1&client_id=\(encoded)")!
        )
    }

    /// The advertised subject type is pairwise, so two RPs must not be handed
    /// the same identifier — otherwise they can discover they share a user.
    func testDifferentRPsGetDifferentSubjects() throws {
        let first = try store.subject(for: "https://one.example/cb")
        let second = try store.subject(for: "https://two.example/cb")
        XCTAssertNotEqual(first, second)
    }

    /// ...while the same RP must recognise the user on the way back.
    func testTheSameRPGetsTheSameSubjectEveryTime() throws {
        let first = try store.subject(for: "https://one.example/cb")
        let again = try store.subject(for: "https://one.example/cb")
        XCTAssertEqual(first, again)
    }

    func testTheTokenCarriesTheSubjectForItsOwnRP() throws {
        let op = SelfIssuedOP(keyStore: store)
        for clientID in ["https://one.example/cb", "https://two.example/cb"] {
            let response = try op.respond(to: try request(clientID: clientID))
            let payload = try SelfIssuedIDTokenValidator.validate(
                idToken: response.idToken,
                expectedAudience: clientID,
                expectedNonce: "n1"
            )
            XCTAssertEqual(payload["sub"] as? String, try op.subject(for: clientID))
        }
    }

    /// The Keychain tag has to be derived from the client_id, or the keys would
    /// collide and the subjects with them.
    func testKeychainTagsDifferPerRP() {
        let one = KeychainKeyStore.tag(prefix: "test", clientID: "https://one.example/cb")
        let two = KeychainKeyStore.tag(prefix: "test", clientID: "https://two.example/cb")
        XCTAssertNotEqual(one, two)
        XCTAssertEqual(one, KeychainKeyStore.tag(prefix: "test", clientID: "https://one.example/cb"))
        XCTAssertTrue(one.hasPrefix("test."))
    }
}

final class SelfIssuedOPTests: XCTestCase {
    private static let keyStore = EphemeralKeyStore()

    private var requestURL: URL {
        URL(string: "openid://?response_type=id_token&client_id=https%3A%2F%2Fclient.example.org%2Fcb&scope=openid%20profile&state=af0ifjsldkj&nonce=n-0S6_WzA2Mj")!
    }

    func testIssuesValidatableIDToken() throws {
        let op = SelfIssuedOP(keyStore: Self.keyStore)
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
        let op = SelfIssuedOP(keyStore: Self.keyStore)
        let response = try op.handle(url: requestURL)
        let (_, payload, _, _) = try JWS.decode(response.idToken)
        let subJWK = try XCTUnwrap(payload["sub_jwk"] as? [String: Any])
        let jwk = RSAPublicJWK(
            n: try XCTUnwrap(subJWK["n"] as? String),
            e: try XCTUnwrap(subJWK["e"] as? String)
        )
        XCTAssertEqual(payload["sub"] as? String, jwk.thumbprint())
        XCTAssertEqual(jwk.thumbprint(), try Self.keyStore.subject(for: "https://client.example.org/cb"))
    }

    func testTamperedPayloadFailsSignatureCheck() throws {
        let op = SelfIssuedOP(keyStore: Self.keyStore)
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
        let op = SelfIssuedOP(keyStore: Self.keyStore)
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

final class IdentityStoreTests: XCTestCase {
    private let one = "https://one.example/cb"
    private let two = "https://two.example/cb"

    /// Counts key generations, so that "creates no key" is asserted rather
    /// than assumed.
    private final class CountingKeys: SIOPIdentityKeys {
        let base = InMemoryIdentityKeys()
        private(set) var created = 0

        func key(tag: String) throws -> SIOPKeyProvider? { try base.key(tag: tag) }
        func createKey(tag: String) throws -> SIOPKeyProvider {
            created += 1
            return try base.createKey(tag: tag)
        }
        func removeKey(tag: String) throws { try base.removeKey(tag: tag) }
    }

    /// An identity answers one RP. Offering it to another would let the two
    /// discover they share a user.
    func testAnRPIsOfferedOnlyItsOwnIdentities() throws {
        let store = SIOPIdentityStore.ephemeral()
        let mine = try store.createIdentity(for: one, label: "a")
        _ = try store.createIdentity(for: two, label: "b")
        XCTAssertEqual(try store.identities(for: one).map(\.id), [mine.id])
    }

    func testSeveralIdentitiesForOneRPPresentDifferentSubjects() throws {
        let store = SIOPIdentityStore.ephemeral()
        let personal = try store.createIdentity(for: one, label: "personal")
        let testing = try store.createIdentity(for: one, label: "testing")
        XCTAssertNotEqual(
            try store.publicJWK(of: personal).thumbprint(),
            try store.publicJWK(of: testing).thumbprint()
        )
    }

    func testRelabellingChangesTheNamesAndNotTheSubject() throws {
        let store = SIOPIdentityStore.ephemeral()
        let identity = try store.createIdentity(for: one, label: "before", note: "")
        let subject = try store.publicJWK(of: identity).thumbprint()

        let renamed = try store.relabel(identity, label: "after", note: "note")

        XCTAssertEqual(renamed.label, "after")
        XCTAssertEqual(renamed.note, "note")
        XCTAssertEqual(try store.publicJWK(of: renamed).thumbprint(), subject)
    }

    func testDeletingRemovesTheKeyAsWellAsTheRecord() throws {
        let store = SIOPIdentityStore.ephemeral()
        let identity = try store.createIdentity(for: one)
        try store.delete(identity)

        XCTAssertTrue(try store.identities(for: one).isEmpty)
        XCTAssertThrowsError(try store.keyProvider(for: identity))
    }

    /// Looking up an RP's identities happens as soon as a request arrives,
    /// before anyone has agreed to anything. It must not cost a key.
    func testLookingUpIdentitiesCreatesNoKey() throws {
        let keys = CountingKeys()
        let store = SIOPIdentityStore(records: InMemoryIdentityRecords(), keys: keys, tagPrefix: "test", adoptsPerRPKeys: true)
        XCTAssertTrue(try store.identities(for: one).isEmpty)
        XCTAssertEqual(keys.created, 0)
    }

    func testTheIdentityUsedLastIsOfferedFirst() throws {
        var clock = Date(timeIntervalSince1970: 0)
        let store = SIOPIdentityStore(records: InMemoryIdentityRecords(), keys: InMemoryIdentityKeys(), tagPrefix: "test", now: { clock })
        let first = try store.createIdentity(for: one, label: "first")
        clock += 1
        let second = try store.createIdentity(for: one, label: "second")
        XCTAssertEqual(try store.identities(for: one).map(\.id), [first.id, second.id], "未使用なら古い順")

        clock += 1
        try store.markUsed(second)
        XCTAssertEqual(try store.identities(for: one).map(\.id), [second.id, first.id])

        clock += 1
        try store.markUsed(first)
        XCTAssertEqual(try store.identities(for: one).map(\.id), [first.id, second.id])
    }

    /// A device that ran the key-per-RP version holds a key for each RP it
    /// answered, and those RPs know the subject that key produces. Taking the
    /// key over keeps the user recognisable to them.
    func testAKeyPerRPKeyIsTakenOverWithTheSubjectTheRPAlreadyKnows() throws {
        let keys = CountingKeys()
        let legacy = try keys.base.createKey(tag: KeychainKeyStore.tag(prefix: "test", clientID: one))
        let store = SIOPIdentityStore(records: InMemoryIdentityRecords(), keys: keys, tagPrefix: "test", adoptsPerRPKeys: true)

        let adopted = try store.identities(for: one)
        XCTAssertEqual(adopted.count, 1)
        XCTAssertEqual(try store.publicJWK(of: adopted[0]).thumbprint(), try legacy.publicJWK().thumbprint())
        XCTAssertNotNil(adopted[0].lastUsedAt, "応答済みの識別子として扱っていない")

        XCTAssertEqual(try store.identities(for: one).count, 1, "引き継ぎを繰り返している")
        XCTAssertTrue(try store.identities(for: two).isEmpty, "別の RP に引き継いでいる")
        XCTAssertEqual(keys.created, 0)
    }

    /// A record that does not decode has to stop the lookup, not vanish from
    /// it: a vanished identity makes its RP look new.
    func testARecordThatDoesNotDecodeIsAnErrorNotAnOmission() throws {
        let identity = try SIOPIdentityStore.ephemeral().createIdentity(for: one, label: "kept")
        let good = try JSONEncoder().encode(identity)
        XCTAssertEqual(try KeychainIdentityRecords.decode([good]).map(\.id), [identity.id])

        XCTAssertThrowsError(try KeychainIdentityRecords.decode([good, Data("{not a record".utf8)])) { error in
            XCTAssertEqual(error as? SIOPError, .unreadableRecord)
        }
    }

    func testATokenSignedAsAnIdentityCarriesItsSubject() throws {
        let store = SIOPIdentityStore.ephemeral()
        let identity = try store.createIdentity(for: one)
        let request = try AuthorizationRequest(
            url: URL(string: "openid://?response_type=id_token&scope=openid&nonce=n1&client_id=https%3A%2F%2Fone.example%2Fcb")!
        )

        let response = try SelfIssuedOP.respond(to: request, signingWith: try store.keyProvider(for: identity))

        let payload = try SelfIssuedIDTokenValidator.validate(idToken: response.idToken, expectedAudience: one, expectedNonce: "n1")
        XCTAssertEqual(payload["sub"] as? String, try store.publicJWK(of: identity).thumbprint())
    }

    /// The consent screen shows what arrived, so the parsed request has to
    /// keep it — in order, and including what the parser does not use.
    func testTheRequestKeepsEveryParameterAsItArrived() throws {
        let request = try AuthorizationRequest(
            url: URL(string: "openid://?response_type=id_token&client_id=https%3A%2F%2Fone.example%2Fcb&scope=openid%20profile&nonce=n1&extra=kept")!
        )
        XCTAssertEqual(request.receivedParameters.map(\.name), ["response_type", "client_id", "scope", "nonce", "extra"])
        XCTAssertEqual(request.receivedParameters.first { $0.name == "scope" }?.value, "openid profile")
    }
}
