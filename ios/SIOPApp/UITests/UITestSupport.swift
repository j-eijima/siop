import XCTest

extension XCTestCase {
    /// iOS confirms before handing a URL to another app. The prompt is
    /// localized, so the affirmative button is matched by position — it is the
    /// last one in the alert — rather than by title, which would tie the tests
    /// to the simulator's language. The prompt lives in a SpringBoard alert
    /// when the URL comes from outside a browser, and in Safari's own in-page
    /// dialog (`SFDialogView`, not a UIAlert) when it comes from a link tap.
    /// Where the prompt lives varies by iOS version, so try each container
    /// that has been observed to host it, longest wait first.
    func confirmAppHandoffIfPresented(inPageDialogOf browser: XCUIApplication? = nil) {
        var containers: [XCUIElement] = []
        if let browser {
            containers.append(browser.otherElements["SFDialogView"])
            containers.append(browser.alerts.firstMatch)
        }
        containers.append(XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch)

        for (index, container) in containers.enumerated() {
            if tapAffirmativeButton(of: container, timeout: index == 0 ? 5 : 1) { return }
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
    func attachScreenOnFailure(trees: [String: XCUIApplication] = [:]) {
        guard testRun?.hasSucceeded == false else { return }
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "failure-screen"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        for (name, app) in trees {
            let dump = XCTAttachment(string: app.debugDescription)
            dump.name = "failure-tree-\(name)"
            dump.lifetime = .keepAlways
            add(dump)
        }
    }
}
