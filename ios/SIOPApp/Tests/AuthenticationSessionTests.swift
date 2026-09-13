import SIOPKit
import XCTest
@testable import SIOPApp

/// What the session does with a request and with the identities behind it.
/// These are questions about state rather than about any screen, so they are
/// answered here exactly, instead of through whatever a particular iOS version
/// does with a URL routed into a running app.
@MainActor
final class AuthenticationSessionTests: XCTestCase {
    private let clientID = "https://client.example.org/cb"

    private func requestURL(nonce: String = "n1") -> URL {
        URL(string: "openid://?response_type=id_token&scope=openid&nonce=\(nonce)&client_id=https%3A%2F%2Fclient.example.org%2Fcb")!
    }

    /// Holds every delivery open until the test says otherwise, keeping what
    /// was sent.
    private final class Deliveries {
        private(set) var urls: [URL] = []
        private(set) var completions: [(Bool) -> Void] = []
        func open(_ url: URL, completion: @escaping (Bool) -> Void) {
            urls.append(url)
            completions.append(completion)
        }
    }

    private func consent(_ session: AuthenticationSession, nonce: String = "n1") throws -> AuthorizationRequest {
        session.receive(requestURL(nonce: nonce))
        guard case let .consent(request) = session.phase else {
            throw XCTSkip("同意画面になっていない: \(session.phase)")
        }
        return request
    }

    /// The subject of the ID Token carried in a redirect, once the RP's own
    /// checks pass.
    private func subject(in redirect: URL) throws -> String? {
        let fragment = try XCTUnwrap(URLComponents(url: redirect, resolvingAgainstBaseURL: false)?.fragment)
        let token = try XCTUnwrap(
            fragment.split(separator: "&")
                .first { $0.hasPrefix("id_token=") }
                .map { String($0.dropFirst("id_token=".count)) }
        )
        let payload = try SelfIssuedIDTokenValidator.validate(idToken: token, expectedAudience: clientID, expectedNonce: "n1")
        return payload["sub"] as? String
    }

    // MARK: - Delivery

    func testDeliveringUntilTheRedirectOpens() throws {
        let deliveries = Deliveries()
        let session = AuthenticationSession(store: .ephemeral(), open: deliveries.open)
        session.approve(try consent(session), as: nil)

        // The response is out but unacknowledged: the consent screen must be
        // gone so its buttons cannot be pressed again.
        guard case let .delivering(clientID) = session.phase else {
            return XCTFail("配送中の状態になっていない")
        }
        XCTAssertEqual(clientID, self.clientID)

        deliveries.completions[0](true)
        guard case .sent = session.phase else {
            return XCTFail("送信済みになっていない")
        }
    }

    func testARedirectNothingOpensIsReportedAsUndeliverable() throws {
        let deliveries = Deliveries()
        let session = AuthenticationSession(store: .ephemeral(), open: deliveries.open)
        session.approve(try consent(session), as: nil)
        deliveries.completions[0](false)

        guard case .undeliverable = session.phase else {
            return XCTFail("渡せなかったことが報告されていない")
        }
    }

    /// A second request can arrive before the first delivery is acknowledged.
    /// The late completion must not replace what it found.
    func testACompletionArrivingAfterANewRequestIsIgnored() throws {
        let deliveries = Deliveries()
        let session = AuthenticationSession(store: .ephemeral(), open: deliveries.open)
        session.approve(try consent(session), as: nil)

        let second = try consent(session, nonce: "n2")
        XCTAssertEqual(second.nonce, "n2")

        // The first delivery finally reports back.
        deliveries.completions[0](true)

        guard case let .consent(stillSecond) = session.phase else {
            return XCTFail("古い応答の完了が新しいリクエストを上書きした")
        }
        XCTAssertEqual(stillSecond.nonce, "n2")
    }

    /// The same must hold once the user has moved on deliberately.
    func testACompletionArrivingAfterResetIsIgnored() throws {
        let deliveries = Deliveries()
        let session = AuthenticationSession(store: .ephemeral(), open: deliveries.open)
        session.approve(try consent(session), as: nil)
        session.reset()

        deliveries.completions[0](true)

        guard case .idle = session.phase else {
            return XCTFail("完了が初期画面を上書きした")
        }
    }

    // MARK: - Identities

    /// `client_id` comes from whoever sent the request, so a request alone
    /// must not cost a key.
    func testReceivingARequestCreatesNoIdentity() throws {
        let session = AuthenticationSession(store: .ephemeral(), open: Deliveries().open)
        _ = try consent(session)
        XCTAssertTrue(session.identities.isEmpty, "リクエストを受け取っただけで識別子を作っている")
    }

    func testDecliningCreatesNoIdentity() throws {
        let deliveries = Deliveries()
        let session = AuthenticationSession(store: .ephemeral(), open: deliveries.open)
        session.decline(try consent(session))

        XCTAssertTrue(session.identities.isEmpty, "拒否したのに識別子を作っている")
        XCTAssertTrue(deliveries.urls[0].absoluteString.contains("error=access_denied"))
    }

    func testTheFirstAnswerToAnRPCreatesOneIdentityAndSignsAsIt() throws {
        let deliveries = Deliveries()
        let session = AuthenticationSession(store: .ephemeral(), open: deliveries.open)
        session.approve(try consent(session), as: nil)

        XCTAssertEqual(session.identities.count, 1)
        let identity = try XCTUnwrap(session.identities.first)
        XCTAssertEqual(identity.clientID, clientID)
        XCTAssertEqual(try subject(in: deliveries.urls[0]), session.subject(of: identity))
    }

    func testTheResponseIsSignedAsTheChosenIdentity() throws {
        let deliveries = Deliveries()
        let session = AuthenticationSession(store: .ephemeral(), open: deliveries.open)
        let personal = try XCTUnwrap(session.createIdentity(for: clientID, label: "個人用", note: ""))
        let testing = try XCTUnwrap(session.createIdentity(for: clientID, label: "テスト用", note: ""))

        session.approve(try consent(session), as: testing)

        XCTAssertEqual(try subject(in: deliveries.urls[0]), session.subject(of: testing))
        XCTAssertNotEqual(session.subject(of: personal), session.subject(of: testing))
        XCTAssertEqual(session.identities.count, 2, "選んだ識別子があるのに新しく作っている")
    }

    /// An identity answering a second RP would hand both the same subject.
    func testAnIdentityNeverAnswersAnotherRP() throws {
        let deliveries = Deliveries()
        let session = AuthenticationSession(store: .ephemeral(), open: deliveries.open)
        let other = try XCTUnwrap(session.createIdentity(for: "https://other.example/cb", label: "別の RP", note: ""))

        session.approve(try consent(session), as: other)

        guard case .failed = session.phase else {
            return XCTFail("別の RP の識別子で応答しようとしている")
        }
        XCTAssertTrue(deliveries.urls.isEmpty, "別の RP の識別子で応答を送っている")
    }

    func testTheIdentityThatAnsweredLastIsOfferedFirst() throws {
        let deliveries = Deliveries()
        let session = AuthenticationSession(store: .ephemeral(), open: deliveries.open)
        _ = try XCTUnwrap(session.createIdentity(for: clientID, label: "a", note: ""))
        let b = try XCTUnwrap(session.createIdentity(for: clientID, label: "b", note: ""))

        session.approve(try consent(session), as: b)

        XCTAssertEqual(session.identities(for: clientID).first?.id, b.id)
    }

    func testRenamingKeepsTheSubject() throws {
        let session = AuthenticationSession(store: .ephemeral(), open: Deliveries().open)
        let identity = try XCTUnwrap(session.createIdentity(for: clientID, label: "before", note: ""))
        let before = session.subject(of: identity)

        session.relabel(identity, label: "after", note: "メモ")

        let renamed = try XCTUnwrap(session.identities.first { $0.id == identity.id })
        XCTAssertEqual(renamed.label, "after")
        XCTAssertEqual(renamed.note, "メモ")
        XCTAssertEqual(session.subject(of: renamed), before)
    }

    /// Keys that cannot be read at all, as when the Keychain refuses.
    private final class UnreadableKeys: SIOPIdentityKeys {
        func key(tag: String) throws -> SIOPKeyProvider? { throw SIOPError.keyStore(-25308) }
        func createKey(tag: String) throws -> SIOPKeyProvider { try SecKeyProvider.generate() }
        func removeKey(tag: String) throws {}
    }

    /// Keys that exist, but stop being readable once told to.
    private final class ForgetfulKeys: SIOPIdentityKeys {
        let base = InMemoryIdentityKeys()
        var forgets = false
        func key(tag: String) throws -> SIOPKeyProvider? {
            if forgets { return nil }
            return try base.key(tag: tag)
        }
        func createKey(tag: String) throws -> SIOPKeyProvider { try base.createKey(tag: tag) }
        func removeKey(tag: String) throws { try base.removeKey(tag: tag) }
    }

    /// Records that cannot be read, as when one no longer decodes.
    private final class UnreadableRecords: SIOPIdentityRecords {
        func loadAll() throws -> [SIOPIdentity] { throw SIOPError.unreadableRecord }
        func save(_ identity: SIOPIdentity) throws {}
        func remove(id: String) throws {}
    }

    /// A record that does not decode must stop the request too: skipping it
    /// would make its RP look new.
    func testARequestStopsWhenARecordCannotBeRead() throws {
        let deliveries = Deliveries()
        let store = SIOPIdentityStore(records: UnreadableRecords(), keys: InMemoryIdentityKeys(), tagPrefix: "test")
        let session = AuthenticationSession(store: store, open: deliveries.open)

        session.receive(requestURL())

        guard case .failed = session.phase else {
            return XCTFail("記録を読めないのに同意画面へ進んでいる")
        }
        XCTAssertTrue(deliveries.urls.isEmpty)
    }

    /// If the identities cannot be read, an RP this device has answered would
    /// look new, and answering it would make a different subject. The request
    /// must stop there rather than reach the consent screen.
    func testARequestStopsWhenIdentitiesCannotBeRead() throws {
        let deliveries = Deliveries()
        let store = SIOPIdentityStore(records: InMemoryIdentityRecords(), keys: UnreadableKeys(), tagPrefix: "test", adoptsPerRPKeys: true)
        let session = AuthenticationSession(store: store, open: deliveries.open)

        session.receive(requestURL())

        guard case .failed = session.phase else {
            return XCTFail("識別子を読めないのに同意画面へ進んでいる")
        }
        XCTAssertTrue(session.identities.isEmpty)
        XCTAssertTrue(deliveries.urls.isEmpty)
    }

    /// An identity that exists but cannot sign right now gets no stand-in:
    /// answering as a new identity would answer as someone else.
    func testAnIdentityThatCannotSignIsNotReplacedUnasked() throws {
        let keys = ForgetfulKeys()
        let deliveries = Deliveries()
        let store = SIOPIdentityStore(records: InMemoryIdentityRecords(), keys: keys, tagPrefix: "test")
        let session = AuthenticationSession(store: store, open: deliveries.open)
        _ = try XCTUnwrap(session.createIdentity(for: clientID, label: "established", note: ""))
        keys.forgets = true

        let request = try consent(session)
        XCTAssertEqual(session.identities.count, 1)
        XCTAssertNil(session.subject(of: session.identities[0]), "読めない鍵の識別子に sub が付いている")

        session.approve(request, as: nil)

        guard case .failed = session.phase else {
            return XCTFail("読めない識別子の代わりに新しい識別子で応答しようとしている")
        }
        XCTAssertEqual(session.identities.count, 1, "代わりの識別子を作っている")
        XCTAssertTrue(deliveries.urls.isEmpty)
    }

    func testDeletingRemovesTheIdentity() throws {
        let session = AuthenticationSession(store: .ephemeral(), open: Deliveries().open)
        let identity = try XCTUnwrap(session.createIdentity(for: clientID, label: "gone", note: ""))

        session.delete(identity)

        XCTAssertTrue(session.identities.isEmpty)
        XCTAssertNil(session.subject(of: identity))
    }
}
