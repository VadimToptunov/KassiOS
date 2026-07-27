import XCTest

/// "Deep" assertions on `KassElement` — checks that look past a bare
/// presence/label match. Split out of `KassElement.swift` to keep that file
/// under the project's line-length budget; these still share `perform`,
/// `textOf`, and the failure-reporting helpers defined there.
public extension KassElement {

    /// Asserts the element's numeric value is within `tolerance` of `expected`.
    /// For money/math where an exact string match is wrong — rounding,
    /// formatting, or locale can all shift the displayed text without the
    /// underlying value being incorrect (e.g. "$92.50" vs. 92.5).
    @discardableResult
    func assertValue(
        closeTo expected: Double, tolerance: Double, file: StaticString = #filePath, line: UInt = #line
    ) -> KassElement {
        perform("assertValue(closeTo: \(expected) ± \(tolerance))", kind: .assert, file: file, line: line) { element in
            guard element.exists else { throw KassError("does not exist") }
            let text = Self.textOf(element)
            guard let actual = KassNumberParsing.parse(text) else {
                throw KassError("could not parse a number out of '\(text)'")
            }
            guard abs(actual - expected) <= tolerance else {
                throw KassError("expected ~\(expected) ±\(tolerance) but found \(actual)")
            }
        }
    }

    /// Asserts the element existed at least once within a short window — for a
    /// transient like a success toast that appears then auto-dismisses. Unlike
    /// `assertVisible` (which waits the *full* flaky-safety budget for the
    /// element to become hittable **now**), this fast-polls existence and
    /// passes on the first sighting, so it can catch something that's already
    /// gone by the time a slower poll would have looked.
    ///
    /// Deliberately bypasses `Waiter`/the interceptor chain: that budget is
    /// tuned for "wait until it's ready", not "catch it while it's here".
    @discardableResult
    func assertAppears(
        within seconds: TimeInterval = 2,
        pollInterval: TimeInterval = 0.05,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> KassElement {
        config.reporter?.stepStarted("assertAppears \(description)")
        let deadline = Date().addingTimeInterval(seconds)
        var sighted = false
        repeat {
            // Cap each sleep at what's left of the budget so a `pollInterval`
            // larger than `within` can't overshoot the documented window.
            config.synchronizer.waitForIdle(timeout: min(pollInterval, max(0, deadline.timeIntervalSinceNow)))
            if resolve().exists {
                sighted = true
                break
            }
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { break }
            RunLoop.current.run(until: Date().addingTimeInterval(min(pollInterval, remaining)))
        } while Date() < deadline

        do {
            if sighted {
                // Same strict-identifier check every other assertion gets via
                // `perform` — a sighting by label-fallback should still be
                // caught under `.enforce`.
                try enforceIdentifierIfNeeded(resolve())
                config.reporter?.stepFinished(status: .passed, message: nil)
            } else {
                throw KassError("did not appear within \(seconds)s")
            }
        } catch {
            let failed = resolve()
            let message = "KassiOS: \(description) — assertAppears failed: \(error)\(failureDiagnostics(for: failed))"
            config.logger.log("❌ \(message)")
            if config.captureScreenshotOnFailure {
                attachFailureScreenshot(label: "assertAppears — \(description)")
            }
            attachDiagnostic(makeDiagnostic(action: "assertAppears", kind: .assert, error: error, file: file, line: line, element: failed))
            config.reporter?.stepFinished(status: .failed, message: message)
            XCTFail(message, file: file, line: line)
        }
        return self
    }
}
