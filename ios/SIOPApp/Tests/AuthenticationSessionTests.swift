import SIOPKit
import XCTest
@testable import SIOPApp

/// The delivery of a response completes asynchronously, so what happens while
/// it is outstanding is a question about this object's state, not about any
/// screen. Testing it here makes the interleaving exact, rather than depending
/// on how a particular iOS version routes a URL into a running app.
@MainActor
final class AuthenticationSessionTests: XCTestCase {
    private let clientID = "https://client.example.org/cb"

    private func requestURL(nonce: String = "n1") -> URL {
        URL(string: "openid://?response_type=id_token&scope=openid&nonce=\(nonce)&client_id=https%3A%2F%2Fclient.example.org%2Fcb")!
    }

    /// Holds every delivery open until the test says otherwise.
    private final class Deliveries {
        private(set) var completions: [(Bool) -> Void] = []
        func open(_ url: URL, completion: @escaping (Bool) -> Void) {
            completions.append(completion)
        }
    }

    func testDeliveringUntilTheRedirectOpens() throws {
        let deliveries = Deliveries()
        let session = AuthenticationSession(keyStore: EphemeralKeyStore(), open: deliveries.open)
        session.receive(requestURL())

        guard case let .consent(request) = session.phase else {
            return XCTFail("同意画面になっていない")
        }
        session.approve(request)

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
        let session = AuthenticationSession(keyStore: EphemeralKeyStore(), open: deliveries.open)
        session.receive(requestURL())
        guard case let .consent(request) = session.phase else {
            return XCTFail("同意画面になっていない")
        }

        session.approve(request)
        deliveries.completions[0](false)

        guard case .undeliverable = session.phase else {
            return XCTFail("渡せなかったことが報告されていない")
        }
    }

    /// A second request can arrive before the first delivery is acknowledged.
    /// The late completion must not replace what it found.
    func testACompletionArrivingAfterANewRequestIsIgnored() throws {
        let deliveries = Deliveries()
        let session = AuthenticationSession(keyStore: EphemeralKeyStore(), open: deliveries.open)
        session.receive(requestURL())
        guard case let .consent(first) = session.phase else {
            return XCTFail("同意画面になっていない")
        }
        session.approve(first)

        session.receive(requestURL(nonce: "n2"))
        guard case let .consent(second) = session.phase else {
            return XCTFail("2 件目の同意画面になっていない")
        }
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
        let session = AuthenticationSession(keyStore: EphemeralKeyStore(), open: deliveries.open)
        session.receive(requestURL())
        guard case let .consent(request) = session.phase else {
            return XCTFail("同意画面になっていない")
        }
        session.approve(request)
        session.reset()

        deliveries.completions[0](true)

        guard case .idle = session.phase else {
            return XCTFail("完了が初期画面を上書きした")
        }
    }
}
