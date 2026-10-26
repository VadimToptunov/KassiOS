import XCTest

final class ReliabilityScreen: KassScreen {
    lazy var liveSwitch = switchControl("rel.liveSwitch")
    lazy var deadSwitch = switchControl("rel.deadSwitch")
    lazy var name = textField("rel.name")
    lazy var price = textField("rel.price")
    lazy var lossy = textField("rel.lossy")
    lazy var ticker = staticText("rel.ticker")
    lazy var steady = staticText("rel.steady")
    lazy var counterButton = button("rel.counter.button")
    lazy var counter = staticText("rel.counter")
    lazy var typing = textField("rel.typing")
    lazy var farButton = button("rel.far.button")
    lazy var farResult = staticText("rel.far.result")
    lazy var bottomButton = button("rel.bottom.button")
    lazy var bottomResult = staticText("rel.bottom.result")

    override var onLoad: [KassElement] { [liveSwitch] }
}

/// KassiOS 1.8.0: outcome checks, auto-scroll, keyboard, one-snapshot reads,
/// time-window asserts and rapid taps, against the demo app's Reliability screen.
final class ReliabilityTests: KassTestCase {

    override func setUp() {
        super.setUp()
        config = KassConfig(timeout: 8, accessibilityIdentifierPolicy: .enforce)
    }

    private func open() { launch(arguments: ["-reliability"]) }

    // 1. Outcome checks

    func test_setSwitch_flipsALiveSwitchAndSaysSo() {
        open()
        onScreen(ReliabilityScreen.self) { screen in
            screen.liveSwitch.setSwitch(on: true).assertHasValue("1")
            screen.liveSwitch.toggle().assertHasValue("0")
        }
    }

    func test_setSwitch_failsOnASwitchThatNeverFlips() {
        open()
        onScreen(ReliabilityScreen.self) { screen in
            XCTExpectFailure("the switch is bound to a constant; a tap can't flip it") {
                screen.deadSwitch.within(timeout: 4).setSwitch(on: true)
            }
            screen.deadSwitch.assertHasValue("0")
        }
    }

    func test_replaceText_checksTheFieldReadsWhatWasTyped() {
        open()
        onScreen(ReliabilityScreen.self) { screen in
            screen.name.replaceText("Alex").assertHasValue("Alex")
            XCTExpectFailure("the field keeps only three characters") {
                screen.lossy.within(timeout: 4).replaceText("12345")
            }
        }
    }

    func test_replaceText_replacesAPrefilledRightAlignedValue() {
        open()
        onScreen(ReliabilityScreen.self) { screen in
            screen.price.replaceText("179.00").assertHasValue("179.00")
            screen.price.clearText()
            screen.price.replaceText("5").assertHasValue("5")
        }
    }

    func test_outcomeChecksCanBeSwitchedOff() {
        config.verifyActionOutcome = false
        open()
        onScreen(ReliabilityScreen.self) { screen in
            screen.deadSwitch.setSwitch(on: true)   // the old behaviour: returns quietly
            screen.deadSwitch.assertHasValue("0")
        }
    }

    // 2. Auto-scroll

    func test_tap_scrollsToAnOffScreenButtonByItself() {
        open()
        onScreen(ReliabilityScreen.self) { screen in
            screen.farButton.tap()
            screen.farResult.assertLabel("far tapped")
        }
    }

    // 3. Keyboard

    func test_tap_dismissesTheKeyboardThatCoversTheTarget() {
        open()
        onScreen(ReliabilityScreen.self) { screen in
            screen.typing.typeText("hello")
            XCTAssertTrue(app.keyboards.firstMatch.exists, "precondition: the keyboard is up")
            screen.bottomButton.tap()
            screen.bottomResult.assertLabel("bottom tapped")
        }
    }

    // 4. One-snapshot reads

    func test_readTexts_readsSeveralElementsAtOnce() {
        open()
        onScreen(ReliabilityScreen.self) { screen in
            let texts = screen.readTexts(["rel.steady", "rel.ticker", "rel.counter"])
            XCTAssertEqual(texts["rel.steady"], "steady")
            XCTAssertEqual(texts["rel.counter"], "0")
            XCTAssertNotNil(texts["rel.ticker"].flatMap(Int.init))
        }
    }

    // 5. Time-window asserts

    func test_assertUnchanged_holdsForAStillValueAndCatchesATickingOne() {
        open()
        onScreen(ReliabilityScreen.self) { screen in
            screen.steady.assertUnchanged(for: 2)
            XCTExpectFailure("the ticker changes every half second") {
                screen.ticker.assertUnchanged(for: 2)
            }
        }
    }

    // 6. Rapid taps

    func test_rapidTap_landsEveryTap() {
        open()
        onScreen(ReliabilityScreen.self) { screen in
            screen.counterButton.rapidTap(times: 3)
            screen.counter.assertLabel("3")
        }
    }

    // Gestures route through the same reachability

    func test_gesturesScrollToAnOffScreenTargetToo() {
        open()
        onScreen(ReliabilityScreen.self) { screen in
            screen.farButton.tapAtNormalizedOffset(x: 0.5, y: 0.5)
            screen.farResult.assertLabel("far tapped")
        }
    }
}
