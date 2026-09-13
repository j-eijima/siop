import XCTest

/// Covers how the app handles a Section 7.3 request: the consent screen it
/// shows, the identities it offers, and the response it produces on approval
/// or refusal.
///
/// The request is injected through a launch argument rather than opened as a
/// URL, because `XCUIApplication.open(_:)` delivers the URL on some iOS
/// versions and merely launches the app on others. That the real `openid:`
/// route works is the job of `EndToEndRPTests`, which goes through Safari.
///
/// Buttons are found by accessibility identifier: the approve button's title
/// depends on whether this RP has an identity yet, which these tests do not
/// all control. Everything else is read as text, so the app is launched in
/// English whatever language the simulator is set to.
final class AuthenticationFlowUITests: XCTestCase {
    private static let clientID = "https://client.example.org/cb"

    override func tearDown() {
        attachScreenOnFailure()
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    private static let english = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]

    private func launch(query: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = Self.english
        if let query {
            app.launchArguments += ["-siopRequestURL", "openid://?\(query)"]
        }
        app.launch()
        return app
    }

    /// A request from an RP no earlier run can have answered, since the
    /// simulator's Keychain outlives each run.
    private func launchForFreshRP() -> (XCUIApplication, String) {
        let clientID = "https://fresh-\(UUID().uuidString.prefix(8).lowercased()).example/cb"
        let encoded = clientID.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        return (launch(query: "response_type=id_token&scope=openid&nonce=n1&client_id=\(encoded)"), clientID)
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
        let app = launch()

        XCTAssertTrue(text(containing: "a separate key for one RP", in: app).waitForExistence(timeout: 20))
        attachScreenshot(app, named: "identity")

        // The Discovery section (Section 7.1) sits below every identity the
        // simulator has accumulated, however many that is. A list builds rows
        // only as they come on screen, so scroll until the row checked last
        // is there, not merely the section's first.
        let issuer = text(containing: "https://self-issued.me", in: app)
        let subjectType = text(containing: "pairwise", in: app)
        for _ in 0..<30 where !subjectType.exists {
            app.swipeUp()
        }
        XCTAssertTrue(subjectType.waitForExistence(timeout: 5))
        XCTAssertTrue(issuer.exists)
    }

    func testRequestShowsConsentScreen() {
        let app = launch(query: "response_type=id_token&client_id=https%3A%2F%2Fclient.example.org%2Fcb&scope=openid%20profile&state=af0ifjsldkj&nonce=n-0S6_WzA2Mj")

        XCTAssertTrue(app.staticTexts[Self.clientID].waitForExistence(timeout: 20))
        XCTAssertTrue(text(containing: "openid", in: app).exists)
        XCTAssertTrue(text(containing: "profile", in: app).exists)
        XCTAssertTrue(text(containing: "n-0S6_WzA2Mj", in: app).exists)
        XCTAssertTrue(app.staticTexts["af0ifjsldkj"].exists, "state がプレビューに無い")
        XCTAssertTrue(app.buttons["approve"].exists)
        XCTAssertTrue(app.buttons["decline"].exists)
        attachScreenshot(app, named: "consent")
    }

    func testApprovalIssuesTokenAndReportsSuccess() {
        let app = launch(query: "response_type=id_token&client_id=https%3A%2F%2Fclient.example.org%2Fcb&scope=openid&nonce=n1")

        XCTAssertTrue(app.buttons["approve"].waitForExistence(timeout: 20))
        app.buttons["approve"].tap()

        XCTAssertTrue(app.staticTexts["ID Token returned"].waitForExistence(timeout: 10))
        // The response must reach the RP in the fragment (Section 3.2.2.5).
        XCTAssertTrue(text(containing: "\(Self.clientID)#id_token=", in: app).exists)
        attachScreenshot(app, named: "approved")
    }

    func testDeclineReportsAccessDenied() {
        let app = launch(query: "response_type=id_token&client_id=https%3A%2F%2Fclient.example.org%2Fcb&scope=openid&nonce=n1")

        XCTAssertTrue(app.buttons["decline"].waitForExistence(timeout: 20))
        app.buttons["decline"].tap()

        XCTAssertTrue(app.staticTexts["Request declined"].waitForExistence(timeout: 10))
        attachScreenshot(app, named: "declined")
    }

    func testARedirectNothingCanOpenIsReportedRatherThanClaimingSuccess() {
        // Section 7.2 lets client_id be any URI, including a scheme no app
        // handles. The token is issued but never reaches the RP.
        let app = launch(query: "response_type=id_token&scope=openid&nonce=n1&client_id=com.example.nothing.handles.this%3A%2F%2Fcb")

        XCTAssertTrue(app.buttons["approve"].waitForExistence(timeout: 20))
        app.buttons["approve"].tap()

        XCTAssertTrue(app.staticTexts["Response not delivered"].waitForExistence(timeout: 20))
    }

    /// An OP is opened from whatever the user was already doing, so it has to
    /// work in whatever orientation the device is being held in — a tablet is
    /// as likely to be in landscape as not.
    func testTheConsentScreenWorksInLandscape() {
        let app = launch(query: "response_type=id_token&client_id=https%3A%2F%2Fclient.example.org%2Fcb&scope=openid%20profile&state=af0ifjsldkj&nonce=n-0S6_WzA2Mj")
        XCTAssertTrue(app.staticTexts[Self.clientID].waitForExistence(timeout: 20))

        XCUIDevice.shared.orientation = .landscapeLeft

        let approve = app.buttons["approve"]
        XCTAssertTrue(approve.waitForExistence(timeout: 10), "横向きで同意画面が失われている")
        XCTAssertTrue(approve.isHittable, "横向きで承認ボタンを押せない")
        XCTAssertTrue(app.staticTexts[Self.clientID].exists, "横向きで要求元が読めない")

        let landscape = XCTAttachment(screenshot: app.screenshot())
        landscape.name = "consent-landscape"
        landscape.lifetime = .keepAlways
        add(landscape)

        approve.tap()
        XCTAssertTrue(app.staticTexts["ID Token returned"].waitForExistence(timeout: 20))
    }

    /// Showing a consent screen must not create a key: the `client_id` comes
    /// from whoever sent the request, so an unanswered stream of them would
    /// otherwise fill the Keychain.
    func testAnUnansweredRequestEstablishesNoIdentifier() {
        let (app, clientID) = launchForFreshRP()
        XCTAssertTrue(app.staticTexts[clientID].waitForExistence(timeout: 20))
        XCTAssertTrue(text(containing: "First request from this requester", in: app).exists)
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
    /// that is now offered for it.
    ///
    /// It has to be approved, not declined: refusing builds an error response
    /// and never reaches key creation, so a declining version of this would
    /// only pass on a device where keys happened to exist already.
    private func subjectAfterAnswering(clientID: String, encoded: String) -> String {
        let query = "response_type=id_token&scope=openid&nonce=n1&client_id=\(encoded)"

        let first = launch(query: query)
        XCTAssertTrue(first.buttons["approve"].waitForExistence(timeout: 20))
        first.buttons["approve"].tap()
        XCTAssertTrue(first.staticTexts["ID Token returned"].waitForExistence(timeout: 20))

        let again = launch(query: query)
        XCTAssertTrue(again.staticTexts[clientID].waitForExistence(timeout: 20))
        return subjectShown(in: again)
    }

    /// The preview shows the whole subject that will be signed; rows elsewhere
    /// shorten it. A JWK thumbprint is 43 base64url characters.
    private func subjectShown(in app: XCUIApplication) -> String {
        let thumbprint = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "[A-Za-z0-9_-]{43}")
        ).firstMatch
        return thumbprint.waitForExistence(timeout: 5) ? thumbprint.label : ""
    }

    /// A second identity for the same RP is a second key, so choosing it
    /// changes the subject that will be signed.
    func testAnIdentityCreatedForTheRPIsOfferedAndSignsTheResponse() {
        let (app, _) = launchForFreshRP()
        XCTAssertTrue(app.buttons["Create identity"].waitForExistence(timeout: 20))
        app.buttons["Create identity"].tap()

        let label = app.textFields["identity-label"]
        XCTAssertTrue(label.waitForExistence(timeout: 10))
        label.tap()
        label.typeText("Personal")
        app.buttons["save-identity"].tap()

        XCTAssertTrue(text(containing: "Personal", in: app).waitForExistence(timeout: 10), "作った識別子が並んでいない")
        XCTAssertFalse(subjectShown(in: app).isEmpty, "作った識別子の sub がプレビューに無い")
        attachScreenshot(app, named: "identity-created")

        app.buttons["approve"].tap()
        XCTAssertTrue(app.staticTexts["ID Token returned"].waitForExistence(timeout: 20))
    }

    /// Deleting takes the key with it, so it asks first, and says what it
    /// does not do.
    func testDeletingAnIdentityAsksFirstAndSaysWhatItLeavesAlone() {
        let (app, _) = launchForFreshRP()
        XCTAssertTrue(app.buttons["Create identity"].waitForExistence(timeout: 20))
        app.buttons["Create identity"].tap()
        let label = app.textFields["identity-label"]
        XCTAssertTrue(label.waitForExistence(timeout: 10))
        label.tap()
        label.typeText("Doomed")
        app.buttons["save-identity"].tap()

        let inspect = app.buttons["Details"].firstMatch
        XCTAssertTrue(inspect.waitForExistence(timeout: 10))
        inspect.tap()
        let delete = app.buttons["delete-identity"]
        XCTAssertTrue(delete.waitForExistence(timeout: 10))
        delete.tap()

        let confirmation = app.alerts.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 10), "確認せずに削除している")
        XCTAssertTrue(
            confirmation.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "does not delete the account the RP holds")).firstMatch.exists,
            "RP 側のアカウントは消えないことを伝えていない"
        )
        attachScreenshot(app, named: "delete-confirmation")
        confirmation.buttons["Delete identity and key"].tap()

        XCTAssertTrue(text(containing: "First request from this requester", in: app).waitForExistence(timeout: 10), "削除した識別子が残っている")
    }

    func testUnsupportedResponseTypeIsRejected() {
        // Section 7.1: a Self-Issued OP supports only response_type=id_token.
        let app = launch(query: "response_type=code&client_id=https%3A%2F%2Fclient.example.org%2Fcb&scope=openid&nonce=n1")

        XCTAssertTrue(app.staticTexts["Could not process the request"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Unsupported response_type: code"].exists)
        attachScreenshot(app, named: "rejected")
    }
}
