import XCTest

/// Full round trip against the test RP in `rp/`: Safari sends the request to
/// the `openid:` endpoint, the app issues the ID Token, and the RP verifies it
/// (OpenID Connect Core 1.0 Section 7.3 - 7.5).
///
/// Requires the RP to be running: `python3 rp/serve.py`.
///
/// Safari is driven explicitly rather than through the default browser. That
/// matters beyond the test: the OP returns the response by opening
/// `redirect_uri`, and iOS hands an https URL to whichever browser is the
/// default. There is no way to return to the browser that started the request,
/// so a round trip only completes when the RP page was opened in the default
/// browser. On the simulator that is always Safari.
final class EndToEndRPTests: XCTestCase {
    private static let rpURL = URL(string: "http://localhost:8080/index.html")!

    private let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")

    override func setUpWithError() throws {
        try skipUnlessRPIsRunning()
        continueAfterFailure = false
    }

    override func tearDown() {
        attachScreenOnFailure(trees: [
            "safari": safari,
            "springboard": XCUIApplication(bundleIdentifier: "com.apple.springboard"),
        ])
        super.tearDown()
    }

    private func skipUnlessRPIsRunning() throws {
        let expectation = XCTestExpectation(description: "RP reachable")
        var reachable = false
        var request = URLRequest(url: Self.rpURL)
        request.timeoutInterval = 5
        URLSession.shared.dataTask(with: request) { _, response, _ in
            reachable = (response as? HTTPURLResponse)?.statusCode == 200
            expectation.fulfill()
        }.resume()
        _ = XCTWaiter.wait(for: [expectation], timeout: 10)
        try XCTSkipUnless(reachable, "テスト RP が起動していません: python3 rp/serve.py")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Safari must be foreground and accessible before it will accept a URL.
    private func openRP() {
        safari.terminate()
        safari.activate()
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 30), "Safari を起動できません")
        safari.open(Self.rpURL)
    }

    func testRPRequestIsIssuedAndVerified() {
        openRP()

        let start = safari.links["SIOP アプリで認証する"]
        XCTAssertTrue(start.waitForExistence(timeout: 30), "RP のページが表示されません")
        attach(safari, "rp-index")
        // Elements exist in the tree while off-screen; only hittable ones tap.
        for _ in 0..<10 where !start.isHittable {
            safari.swipeUp()
        }
        start.tap()

        let app = XCUIApplication()
        let approve = app.buttons["この識別子で応答する"]
        XCTAssertTrue(waitForElement(approve, inPageDialogOf: safari), "同意画面が表示されません")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "e2e-consent"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        approve.tap()

        // Section 7.5: the RP verifies iss / sub / sub_jwk / signature / aud / nonce.
        XCTAssertTrue(safari.staticTexts["検証に成功しました"].waitForExistence(timeout: 30),
                      "RP がトークンを検証できませんでした")
        let verified = XCTAttachment(screenshot: safari.screenshot())
        verified.name = "e2e-verified"
        verified.lifetime = .keepAlways
        add(verified)
    }
}
