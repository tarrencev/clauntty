import XCTest
@testable import Clauntty

final class KeyboardAccessoryViewTests: XCTestCase {

    var accessoryView: KeyboardAccessoryView!
    var receivedData: Data?

    override func setUp() {
        super.setUp()
        KeyboardBarLayoutStore.reset()
        accessoryView = KeyboardAccessoryView(frame: CGRect(x: 0, y: 0, width: 400, height: 60))
        accessoryView.onKeyInput = { [weak self] data in
            self?.receivedData = data
        }
    }

    override func tearDown() {
        KeyboardBarLayoutStore.reset()
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
        XCTAssertNotNil(findButton(accessibilityId: "Backtick"))
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

    func testSnippetSlotSendsConfiguredText() {
        let customLayout = KeyboardBarLayout(
            leftSlots: [
                KeyboardBarAction(kind: .snippet, snippetText: "echo hi", snippetLabel: "Run"),
                .fixed(.empty),
                .fixed(.empty),
                .fixed(.empty),
            ],
            rightSlots: [
                .fixed(.empty),
                .fixed(.empty),
                .fixed(.empty),
                .fixed(.empty),
            ]
        )
        KeyboardBarLayoutStore.save(customLayout)
        NotificationCenter.default.post(name: .keyboardBarLayoutChanged, object: nil)
        accessoryView.layoutIfNeeded()

        let snippetButton = findButton(accessibilityId: "Snippet")
        XCTAssertNotNil(snippetButton)
        XCTAssertEqual(snippetButton?.title(for: .normal), "Run")

        snippetButton?.sendActions(for: .touchUpInside)
        XCTAssertEqual(receivedData, "echo hi".data(using: .utf8))
    }

    func testSnippetSlotRunOnTapAppendsCarriageReturn() {
        let customLayout = KeyboardBarLayout(
            leftSlots: [
                KeyboardBarAction(kind: .snippet, snippetText: "echo hi", snippetLabel: "Run", snippetRunOnTap: true),
                .fixed(.empty),
                .fixed(.empty),
                .fixed(.empty),
            ],
            rightSlots: [
                .fixed(.empty),
                .fixed(.empty),
                .fixed(.empty),
                .fixed(.empty),
            ]
        )
        KeyboardBarLayoutStore.save(customLayout)
        NotificationCenter.default.post(name: .keyboardBarLayoutChanged, object: nil)
        accessoryView.layoutIfNeeded()

        let snippetButton = findButton(accessibilityId: "Snippet")
        XCTAssertNotNil(snippetButton)

        snippetButton?.sendActions(for: .touchUpInside)
        XCTAssertEqual(receivedData, "echo hi\r".data(using: .utf8))
    }

    func testCustomKeySlotSendsConfiguredText() {
        let customLayout = KeyboardBarLayout(
            leftSlots: [
                KeyboardBarAction(kind: .customKey, customText: "~", customLabel: "Tilde"),
                .fixed(.empty),
                .fixed(.empty),
                .fixed(.empty),
            ],
            rightSlots: [
                .fixed(.empty),
                .fixed(.empty),
                .fixed(.empty),
                .fixed(.empty),
            ]
        )
        KeyboardBarLayoutStore.save(customLayout)
        NotificationCenter.default.post(name: .keyboardBarLayoutChanged, object: nil)
        accessoryView.layoutIfNeeded()

        let customButton = findButton(accessibilityId: "CustomKey")
        XCTAssertNotNil(customButton)
        customButton?.sendActions(for: .touchUpInside)
        XCTAssertEqual(receivedData, "~".data(using: .utf8))
    }

    func testFnThenCustomDigitMapsToFunctionKey() {
        let customLayout = KeyboardBarLayout(
            leftSlots: [
                .fixed(.fn),
                KeyboardBarAction(kind: .customKey, customText: "1", customLabel: "1"),
                .fixed(.empty),
                .fixed(.empty),
            ],
            rightSlots: [
                .fixed(.empty),
                .fixed(.empty),
                .fixed(.empty),
                .fixed(.empty),
            ]
        )
        KeyboardBarLayoutStore.save(customLayout)
        NotificationCenter.default.post(name: .keyboardBarLayoutChanged, object: nil)
        accessoryView.layoutIfNeeded()

        let fnButton = findButton(accessibilityId: "Fn")
        let customButton = findButton(accessibilityId: "CustomKey")
        XCTAssertNotNil(fnButton)
        XCTAssertNotNil(customButton)

        fnButton?.sendActions(for: .touchUpInside)
        customButton?.sendActions(for: .touchUpInside)

        XCTAssertEqual(receivedData, Data([0x1B, 0x4F, 0x50])) // F1
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
