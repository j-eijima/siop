import XCTest

extension XCTestCase {
    /// iOS confirms before handing a URL to another app. The prompt is
    /// localized, so the affirmative button is matched by position — it is the
    /// last one in the alert — rather than by title, which would tie the tests
    /// to the simulator's language. The prompt lives in a SpringBoard alert
    /// when the URL comes from outside a browser, and in Safari's own in-page
    /// dialog (`SFDialogView`, not a UIAlert) when it comes from a link tap.
    func confirmAppHandoffIfPresented(inPageDialogOf browser: XCUIApplication? = nil) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if tapAffirmativeButton(of: springboard.alerts.firstMatch) { return }
        if let browser {
            _ = tapAffirmativeButton(of: browser.otherElements["SFDialogView"])
        }
    }

    private func tapAffirmativeButton(of container: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        guard container.waitForExistence(timeout: timeout) else { return false }
        let buttons = container.buttons
        guard buttons.count > 0 else { return false }
        buttons.element(boundBy: buttons.count - 1).tap()
        return true
    }

    /// Waits for `element`, clearing the handoff confirmation if that is what
    /// stands in the way. Costs nothing when no confirmation is shown.
    @discardableResult
    func waitForElement(
        _ element: XCUIElement,
        firstTimeout: TimeInterval = 8,
        timeout: TimeInterval = 20,
        inPageDialogOf browser: XCUIApplication? = nil
    ) -> Bool {
        if element.waitForExistence(timeout: firstTimeout) { return true }
        confirmAppHandoffIfPresented(inPageDialogOf: browser)
        return element.waitForExistence(timeout: timeout)
    }

    /// Whatever is actually on screen when a test fails — the only way to tell
    /// an undismissed system prompt from a genuinely broken screen on CI.
    func attachScreenOnFailure() {
        guard testRun?.hasSucceeded == false else { return }
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "failure-screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
