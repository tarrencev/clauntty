import XCTest
@testable import Clauntty

final class KeyboardBarConfigTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: KeyboardBarLayoutStore.userDefaultsKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: KeyboardBarLayoutStore.userDefaultsKey)
        super.tearDown()
    }

    func testLoadReturnsDefaultWhenMissing() {
        let layout = KeyboardBarLayoutStore.load()
        XCTAssertEqual(layout, KeyboardBarLayout.default.normalized())
    }

    func testSaveLoadRoundTripWithSnippet() {
        let layout = KeyboardBarLayout(
            leftSlots: [
                .fixed(.mic),
                KeyboardBarAction(kind: .snippet, snippetText: "ls -la", snippetLabel: "List", snippetRunOnTap: true),
                .fixed(.esc),
                .fixed(.ctrl),
            ],
            rightSlots: [
                .fixed(.enter),
                .fixed(.ctrlC),
                .fixed(.empty),
                .fixed(.f2),
            ]
        )

        KeyboardBarLayoutStore.save(layout)
        let loaded = KeyboardBarLayoutStore.load()
        XCTAssertEqual(loaded, layout.normalized())
        XCTAssertEqual(loaded.leftSlots[1].snippetRunOnTap, true)
    }

    func testLoadFallsBackToDefaultForInvalidData() {
        UserDefaults.standard.set(Data([0x01, 0x02, 0x03]), forKey: KeyboardBarLayoutStore.userDefaultsKey)
        let loaded = KeyboardBarLayoutStore.load()
        XCTAssertEqual(loaded, KeyboardBarLayout.default.normalized())
    }

    func testNormalizedPadsMissingSlotsWithEmpty() {
        let partial = KeyboardBarLayout(
            leftSlots: [.fixed(.mic)],
            rightSlots: [.fixed(.enter), .fixed(.ctrlC)]
        )
        let normalized = partial.normalized()
        XCTAssertEqual(normalized.leftSlots.count, KeyboardBarLayout.leftSlotCount)
        XCTAssertEqual(normalized.rightSlots.count, KeyboardBarLayout.rightSlotCount)
        XCTAssertEqual(normalized.leftSlots[1].kind, .empty)
        XCTAssertEqual(normalized.rightSlots[2].kind, .empty)
    }

    func testSaveLoadRoundTripWithHoldActionAndCustomKey() {
        var primary = KeyboardBarAction(kind: .customKey, customText: "`", customLabel: "Tick")
        primary.setHoldAction(KeyboardBarAction(kind: .customKey, customText: "~", customLabel: "Tilde"))

        let layout = KeyboardBarLayout(
            leftSlots: [primary, .fixed(.fn), .fixed(.empty), .fixed(.empty)],
            rightSlots: [.fixed(.enter), .fixed(.empty), .fixed(.empty), .fixed(.empty)]
        )

        KeyboardBarLayoutStore.save(layout)
        let loaded = KeyboardBarLayoutStore.load()
        XCTAssertEqual(loaded, layout.normalized())
        XCTAssertEqual(loaded.leftSlots[0].holdKind, .customKey)
        XCTAssertEqual(loaded.leftSlots[0].holdCustomText, "~")
    }

    func testSaveLoadRoundTripWithHoldSnippetRunOnTap() {
        var primary = KeyboardBarAction(kind: .empty)
        primary.setHoldAction(
            KeyboardBarAction(
                kind: .snippet,
                snippetText: "tmux new-window",
                snippetLabel: "tmux",
                snippetRunOnTap: true
            )
        )

        let layout = KeyboardBarLayout(
            leftSlots: [primary, .fixed(.fn), .fixed(.empty), .fixed(.empty)],
            rightSlots: [.fixed(.enter), .fixed(.empty), .fixed(.empty), .fixed(.empty)]
        )

        KeyboardBarLayoutStore.save(layout)
        let loaded = KeyboardBarLayoutStore.load()
        XCTAssertEqual(loaded.leftSlots[0].holdKind, .snippet)
        XCTAssertEqual(loaded.leftSlots[0].holdSnippetRunOnTap, true)
    }
}
