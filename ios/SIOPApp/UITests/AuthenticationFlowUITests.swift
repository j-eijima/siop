import XCTest

/// Drives the app through the `openid:` authorization endpoint the way an RP
/// would (OpenID Connect Core 1.0 Section 7.3).
final class AuthenticationFlowUITests: XCTestCase {
    private static let clientID = "https://client.example.org/cb"

    private func launch(query: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.open(URL(string: "openid://?\(query)")!)
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

        XCTAssertTrue(app.staticTexts[Self.clientID].waitForExistence(timeout: 10))
        XCTAssertTrue(text(containing: "openid", in: app).exists)
        XCTAssertTrue(text(containing: "profile", in: app).exists)
        XCTAssertTrue(text(containing: "n-0S6_WzA2Mj", in: app).exists)
        XCTAssertTrue(app.buttons["この識別子で応答する"].exists)
        XCTAssertTrue(app.buttons["拒否する"].exists)
        attachScreenshot(app, named: "consent")
    }

    func testApprovalIssuesTokenAndReportsSuccess() {
        let app = launch(query: "response_type=id_token&client_id=https%3A%2F%2Fclient.example.org%2Fcb&scope=openid&nonce=n1")

        XCTAssertTrue(app.buttons["この識別子で応答する"].waitForExistence(timeout: 10))
        app.buttons["この識別子で応答する"].tap()

        XCTAssertTrue(app.staticTexts["ID Token を返しました"].waitForExistence(timeout: 10))
        // The response must reach the RP in the fragment (Section 3.2.2.5).
        XCTAssertTrue(text(containing: "\(Self.clientID)#id_token=", in: app).exists)
        attachScreenshot(app, named: "approved")
    }

    func testDeclineReportsAccessDenied() {
        let app = launch(query: "response_type=id_token&client_id=https%3A%2F%2Fclient.example.org%2Fcb&scope=openid&nonce=n1")

        XCTAssertTrue(app.buttons["拒否する"].waitForExistence(timeout: 10))
        app.buttons["拒否する"].tap()

        XCTAssertTrue(app.staticTexts["リクエストを拒否しました"].waitForExistence(timeout: 10))
        attachScreenshot(app, named: "declined")
    }

    func testUnsupportedResponseTypeIsRejected() {
        // Section 7.1: a Self-Issued OP supports only response_type=id_token.
        let app = launch(query: "response_type=code&client_id=https%3A%2F%2Fclient.example.org%2Fcb&scope=openid&nonce=n1")

        XCTAssertTrue(app.staticTexts["処理できませんでした"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["未対応の response_type です: code"].exists)
        attachScreenshot(app, named: "rejected")
    }
}
