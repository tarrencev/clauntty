import XCTest
@testable import Clauntty

final class KeyboardAccessoryViewTests: XCTestCase {

    var accessoryView: KeyboardAccessoryView!
    var receivedData: Data?

    override func setUp() {
        super.setUp()
        accessoryView = KeyboardAccessoryView(frame: CGRect(x: 0, y: 0, width: 400, height: 60))
        accessoryView.onKeyInput = { [weak self] data in
            self?.receivedData = data
        }
    }

    override func tearDown() {
        accessoryView = nil
        receivedData = nil
        super.tearDown()
    }

    func testAccessoryViewHasExpectedButtons() {
        accessoryView.layoutIfNeeded()

        XCTAssertNotNil(findButton(accessibilityId: "Mic"))
        XCTAssertNotNil(findButton(accessibilityId: "Esc"))
        XCTAssertNotNil(findButton(accessibilityId: "Tab"))
        XCTAssertNotNil(findButton(accessibilityId: "Ctrl"))
        XCTAssertNotNil(findButton(accessibilityId: "^C"))
        XCTAssertNotNil(findButton(accessibilityId: "^O"))
        XCTAssertNotNil(findButton(accessibilityId: "^B"))
        XCTAssertNotNil(findButton(accessibilityId: "Enter"))
    }

    func testEscButtonSendsEscapeSequence() {
        let escButton = findButton(accessibilityId: "Esc")
        XCTAssertNotNil(escButton)

        escButton?.sendActions(for: .touchUpInside)
        XCTAssertEqual(receivedData, Data([0x1B]))
    }

    func testCtrlCButtonSendsETX() {
        let ctrlCButton = findButton(accessibilityId: "^C")
        XCTAssertNotNil(ctrlCButton)

        ctrlCButton?.sendActions(for: .touchUpInside)
        XCTAssertEqual(receivedData, Data([0x03]))
    }

    func testJoystickDoubleTapTriggersCallback() {
        var didTriggerDoubleTap = false
        accessoryView.onJoystickDoubleTap = {
            didTriggerDoubleTap = true
        }

        guard let nippleView = findView(in: accessoryView, ofType: ArrowNippleView.self) else {
            XCTFail("Expected ArrowNippleView to exist")
            return
        }

        let selector = NSSelectorFromString("handleDoubleTap")
        XCTAssertTrue(nippleView.responds(to: selector))
        _ = nippleView.perform(selector)

        XCTAssertTrue(didTriggerDoubleTap)
    }

    private func findButton(accessibilityId: String) -> UIButton? {
        findView(in: accessoryView, ofType: UIButton.self) { button in
            button.accessibilityIdentifier == accessibilityId
        }
    }

    private func findView<T: UIView>(in root: UIView, ofType type: T.Type, predicate: ((T) -> Bool)? = nil) -> T? {
        if let typed = root as? T, predicate?(typed) ?? true {
            return typed
        }
        for subview in root.subviews {
            if let found: T = findView(in: subview, ofType: type, predicate: predicate) {
                return found
            }
        }
        return nil
    }
}
