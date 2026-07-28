import XCTest
@testable import KassiOS

final class KassIdentifierSuggestionsTests: XCTestCase {

    // MARK: - levenshtein

    func test_levenshtein_identicalStrings() {
        XCTAssertEqual(KassIdentifierSuggestions.levenshtein("welcome", "welcome"), 0)
    }

    func test_levenshtein_singleSubstitution() {
        XCTAssertEqual(KassIdentifierSuggestions.levenshtein("cat", "cot"), 1)
    }

    func test_levenshtein_singleDeletion() {
        XCTAssertEqual(KassIdentifierSuggestions.levenshtein("login.submit", "login.submt"), 1)
    }

    func test_levenshtein_singleInsertion() {
        XCTAssertEqual(KassIdentifierSuggestions.levenshtein("submt", "submit"), 1)
    }

    func test_levenshtein_emptyStrings() {
        XCTAssertEqual(KassIdentifierSuggestions.levenshtein("", ""), 0)
        XCTAssertEqual(KassIdentifierSuggestions.levenshtein("", "abc"), 3)
        XCTAssertEqual(KassIdentifierSuggestions.levenshtein("abc", ""), 3)
    }

    func test_levenshtein_completelyDifferentStrings() {
        XCTAssertEqual(KassIdentifierSuggestions.levenshtein("login.submit", "home.title"), 10)
    }

    // MARK: - nearest

    func test_nearest_ranksClosestFirstAndDropsUnrelated() {
        let result = KassIdentifierSuggestions.nearest(
            to: "login.submit",
            among: ["login.submitButton", "home.title", "login.submt"]
        )
        // "login.submt" (distance 1) ranks before "login.submitButton" (distance
        // 6); the unrelated "home.title" is dropped by the distance cap.
        XCTAssertEqual(result, ["login.submt", "login.submitButton"])
    }

    func test_nearest_dropsExactCaseInsensitiveMatch() {
        let result = KassIdentifierSuggestions.nearest(to: "signIn", among: ["SIGNIN", "signOut"])
        XCTAssertEqual(result, ["signOut"])
    }

    func test_nearest_respectsMaxCount() {
        let result = KassIdentifierSuggestions.nearest(
            to: "row",
            among: ["row1", "row2", "row3", "row4"],
            max: 2
        )
        XCTAssertEqual(result.count, 2)
    }

    func test_nearest_emptyTargetYieldsNoSuggestions() {
        XCTAssertEqual(KassIdentifierSuggestions.nearest(to: "", among: ["anything"]), [])
    }

    func test_nearest_emptyCandidatesYieldNothing() {
        XCTAssertEqual(KassIdentifierSuggestions.nearest(to: "welcome", among: []), [])
    }

    func test_nearest_dedupesCaseInsensitiveDuplicates() {
        let result = KassIdentifierSuggestions.nearest(to: "welcome", among: ["welcom", "Welcom"])
        XCTAssertEqual(result, ["welcom"])
    }

    func test_nearest_respectsExplicitMaxDistance() {
        // "home.title" is 10 edits away — excluded even under the widened cap
        // is impossible to prove without a huge cap, so prove the opposite:
        // a tiny explicit cap excludes even a close candidate.
        let result = KassIdentifierSuggestions.nearest(
            to: "login.submit", among: ["login.submt"], maxDistance: 0
        )
        XCTAssertEqual(result, [])
    }

    /// A ~40-char, realistic identifier among several equally verbose but
    /// genuinely unrelated ones (different screens/domains, no shared
    /// structure). The default cap is a *ratio* of the target's length
    /// (`target.count / 2`), which sounds generous for a long id — this proves
    /// it still degrades to "nothing" rather than surfacing distant noise: for
    /// strings this long, two unrelated identifiers differ in most of their
    /// characters, so their distance lands far above even a generous ratio cap.
    func test_nearest_longIdentifier_dropsUnrelatedVerboseNoise() {
        let target = "checkout.payment.creditCard.expiryMonth"
        let unrelated = [
            "settings.notifications.pushToggleSwitchControl",
            "profile.editAvatar.uploadProgressIndicator",
            "onboarding.welcomeCarousel.pageControlDots",
            "search.filters.priceRangeSliderThumbHandle",
            "cart.summary.discountCodeApplyButtonLabel"
        ]
        XCTAssertEqual(KassIdentifierSuggestions.nearest(to: target, among: unrelated), [])
    }

    /// The same long target still surfaces a genuinely close sibling — proves
    /// the previous test isn't passing merely because the cap is too tight to
    /// suggest anything at that length.
    func test_nearest_longIdentifier_stillSurfacesACloseSibling() {
        let target = "checkout.payment.creditCard.expiryMonth"
        let result = KassIdentifierSuggestions.nearest(to: target, among: ["checkout.payment.creditCard.expiryYear"])
        XCTAssertEqual(result, ["checkout.payment.creditCard.expiryYear"])
    }
}
