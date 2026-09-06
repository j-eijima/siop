import XCTest

/// Covers how the app handles a Section 7.3 request: the consent screen it
/// shows, and the response it produces on approval or refusal.
///
/// The request is injected through a launch argument rather than opened as a
/// URL, because `XCUIApplication.open(_:)` delivers the URL on some iOS
/// versions and merely launches the app on others. That the real `openid:`
/// route works is the job of `EndToEndRPTests`, which goes through Safari.
final class AuthenticationFlowUITests: XCTestCase {
    private static let clientID = "https://client.example.org/cb"

    override func tearDown() {
        attachScreenOnFailure()
        super.tearDown()
    }

    private func launch(query: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-siopRequestURL", "openid://?\(query)"]
        app.launch()
        return app
    }

    /// `LabeledContent` merges its label and value into one accessibility
    /// element, so match on a substring rather than the whole label.
    private func text(containing value: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", value)).firstMatch
    }

    private func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testIdentityScreenShowsSelfIssuedSubject() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["sub"].waitForExistence(timeout: 10))
        attachScreenshot(app, named: "identity")

        // The Discovery section (Section 7.1) sits below the fold.
        app.swipeUp()
        XCTAssertTrue(text(containing: "https://self-issued.me", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(text(containing: "openid:", in: app).exists)
    }

    func testRequestShowsConsentScreen() {
        let app = launch(query: "response_type=id_token&client_id=https%3A%2F%2Fclient.example.org%2Fcb&scope=openid%20profile&state=af0ifjsldkj&nonce=n-0S6_WzA2Mj")

        XCTAssertTrue(app.staticTexts[Self.clientID].waitForExistence(timeout: 20))
        XCTAssertTrue(text(containing: "openid", in: app).exists)
        XCTAssertTrue(text(containing: "profile", in: app).exists)
        XCTAssertTrue(text(containing: "n-0S6_WzA2Mj", in: app).exists)
        XCTAssertTrue(app.buttons["この識別子で応答する"].exists)
        XCTAssertTrue(app.buttons["拒否する"].exists)
        attachScreenshot(app, named: "consent")
    }

    func testApprovalIssuesTokenAndReportsSuccess() {
        let app = launch(query: "response_type=id_token&client_id=https%3A%2F%2Fclient.example.org%2Fcb&scope=openid&nonce=n1")

        XCTAssertTrue(app.buttons["この識別子で応答する"].waitForExistence(timeout: 20))
        app.buttons["この識別子で応答する"].tap()

        XCTAssertTrue(app.staticTexts["ID Token を返しました"].waitForExistence(timeout: 10))
        // The response must reach the RP in the fragment (Section 3.2.2.5).
        XCTAssertTrue(text(containing: "\(Self.clientID)#id_token=", in: app).exists)
        attachScreenshot(app, named: "approved")
    }

    func testDeclineReportsAccessDenied() {
        let app = launch(query: "response_type=id_token&client_id=https%3A%2F%2Fclient.example.org%2Fcb&scope=openid&nonce=n1")

        XCTAssertTrue(app.buttons["拒否する"].waitForExistence(timeout: 20))
        app.buttons["拒否する"].tap()

        XCTAssertTrue(app.staticTexts["リクエストを拒否しました"].waitForExistence(timeout: 10))
        attachScreenshot(app, named: "declined")
    }

    func testARedirectNothingCanOpenIsReportedRatherThanClaimingSuccess() {
        // Section 7.2 lets client_id be any URI, including a scheme no app
        // handles. The token is issued but never reaches the RP.
        let app = launch(query: "response_type=id_token&scope=openid&nonce=n1&client_id=com.example.nothing.handles.this%3A%2F%2Fcb")

        XCTAssertTrue(app.buttons["この識別子で応答する"].waitForExistence(timeout: 20))
        app.buttons["この識別子で応答する"].tap()

        XCTAssertTrue(app.staticTexts["応答を渡せませんでした"].waitForExistence(timeout: 20))
    }

    func testUnsupportedResponseTypeIsRejected() {
        // Section 7.1: a Self-Issued OP supports only response_type=id_token.
        let app = launch(query: "response_type=code&client_id=https%3A%2F%2Fclient.example.org%2Fcb&scope=openid&nonce=n1")

        XCTAssertTrue(app.staticTexts["処理できませんでした"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["未対応の response_type です: code"].exists)
        attachScreenshot(app, named: "rejected")
    }
}
