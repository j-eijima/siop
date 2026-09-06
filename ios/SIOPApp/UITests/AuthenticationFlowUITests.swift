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
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    private func launch(query: String, deliveryDelaySeconds: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-siopRequestURL", "openid://?\(query)"]
        if let deliveryDelaySeconds {
            app.launchArguments += ["-siopDeliveryDelaySeconds", deliveryDelaySeconds]
        }
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

        XCTAssertTrue(text(containing: "RP ごとに別の鍵", in: app).waitForExistence(timeout: 20))
        attachScreenshot(app, named: "identity")

        // The Discovery section (Section 7.1) sits below the fold.
        app.swipeUp()
        XCTAssertTrue(text(containing: "https://self-issued.me", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(text(containing: "pairwise", in: app).exists)
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

    /// Opening a redirect completes asynchronously, so a second request can
    /// arrive first. The late completion must not replace what it found.
    func testACompletionArrivingAfterANewRequestDoesNotOverwriteIt() {
        let app = launch(
            query: "response_type=id_token&scope=openid&nonce=n1&client_id=com.example.nothing.handles.this%3A%2F%2Fcb",
            deliveryDelaySeconds: "6"
        )
        XCTAssertTrue(app.buttons["この識別子で応答する"].waitForExistence(timeout: 20))
        app.buttons["この識別子で応答する"].tap()
        XCTAssertTrue(app.staticTexts["応答を返しています"].waitForExistence(timeout: 10))

        // A second request while the first delivery is still outstanding.
        app.open(URL(string: "openid://?response_type=id_token&scope=openid&nonce=n2&client_id=https%3A%2F%2Fsecond.example.org%2Fcb")!)
        XCTAssertTrue(app.staticTexts["https://second.example.org/cb"].waitForExistence(timeout: 20))

        // Long enough for the first delivery to complete behind it.
        XCTAssertFalse(
            app.staticTexts["応答を渡せませんでした"].waitForExistence(timeout: 10),
            "古い応答の完了が新しいリクエストの画面を上書きしている"
        )
        XCTAssertTrue(app.staticTexts["https://second.example.org/cb"].exists)
    }

    /// An OP is opened from whatever the user was already doing, so it has to
    /// work in whatever orientation the device is being held in — a tablet is
    /// as likely to be in landscape as not.
    func testTheConsentScreenWorksInLandscape() {
        let app = launch(query: "response_type=id_token&client_id=https%3A%2F%2Fclient.example.org%2Fcb&scope=openid%20profile&state=af0ifjsldkj&nonce=n-0S6_WzA2Mj")
        XCTAssertTrue(app.staticTexts[Self.clientID].waitForExistence(timeout: 20))

        XCUIDevice.shared.orientation = .landscapeLeft

        let approve = app.buttons["この識別子で応答する"]
        XCTAssertTrue(approve.waitForExistence(timeout: 10), "横向きで同意画面が失われている")
        XCTAssertTrue(approve.isHittable, "横向きで承認ボタンを押せない")
        XCTAssertTrue(app.staticTexts[Self.clientID].exists, "横向きで要求元が読めない")

        let landscape = XCTAttachment(screenshot: app.screenshot())
        landscape.name = "consent-landscape"
        landscape.lifetime = .keepAlways
        add(landscape)

        approve.tap()
        XCTAssertTrue(app.staticTexts["ID Token を返しました"].waitForExistence(timeout: 20))
    }

    /// Showing a consent screen must not create a key: the `client_id` comes
    /// from whoever sent the request, so an unanswered stream of them would
    /// otherwise fill the Keychain.
    func testAnUnansweredRequestEstablishesNoIdentifier() {
        let app = launch(query: "response_type=id_token&scope=openid&nonce=n1&client_id=https%3A%2F%2Ffresh.example%2Fcb")
        XCTAssertTrue(app.staticTexts["https://fresh.example/cb"].waitForExistence(timeout: 20))
        XCTAssertTrue(text(containing: "この要求元は初めてです", in: app).exists)
        XCTAssertTrue(subjectShown(in: app).isEmpty, "応答前に識別子を作っている")
    }

    /// The subject is the thumbprint of a key made for one RP, so a second RP
    /// must be shown a different one — once each has been answered.
    func testEachRPIsShownItsOwnSubject() {
        let firstSubject = subjectAfterAnswering(clientID: "https://one.example/cb", encoded: "https%3A%2F%2Fone.example%2Fcb")
        let secondSubject = subjectAfterAnswering(clientID: "https://two.example/cb", encoded: "https%3A%2F%2Ftwo.example%2Fcb")

        XCTAssertFalse(firstSubject.isEmpty, "応答後も識別子が確立していない")
        XCTAssertNotEqual(firstSubject, secondSubject, "別の RP に同じ識別子を提示している")
    }

    /// Answers the RP once, then reopens the same request to read the subject
    /// that is now established for it.
    ///
    /// It has to be approved, not declined: refusing builds an error response
    /// and never reaches key creation, so a declining version of this would
    /// only pass on a device where keys happened to exist already.
    private func subjectAfterAnswering(clientID: String, encoded: String) -> String {
        let query = "response_type=id_token&scope=openid&nonce=n1&client_id=\(encoded)"

        let first = launch(query: query)
        XCTAssertTrue(first.buttons["この識別子で応答する"].waitForExistence(timeout: 20))
        first.buttons["この識別子で応答する"].tap()
        XCTAssertTrue(first.staticTexts["ID Token を返しました"].waitForExistence(timeout: 20))

        let again = launch(query: query)
        XCTAssertTrue(again.staticTexts[clientID].waitForExistence(timeout: 20))
        return subjectShown(in: again)
    }

    /// The consent screen shows the subject under its own heading, when one
    /// has been established. A JWK thumbprint is 43 base64url characters.
    private func subjectShown(in app: XCUIApplication) -> String {
        let thumbprint = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "[A-Za-z0-9_-]{43}")
        ).firstMatch
        return thumbprint.waitForExistence(timeout: 5) ? thumbprint.label : ""
    }

    func testUnsupportedResponseTypeIsRejected() {
        // Section 7.1: a Self-Issued OP supports only response_type=id_token.
        let app = launch(query: "response_type=code&client_id=https%3A%2F%2Fclient.example.org%2Fcb&scope=openid&nonce=n1")

        XCTAssertTrue(app.staticTexts["処理できませんでした"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["未対応の response_type です: code"].exists)
        attachScreenshot(app, named: "rejected")
    }
}
