# AUDIT.md — Phase 0 (KassiOS @ v0.10.0, commit 087803d)

Blocking audit per `KassiOS-Roadmap.md` §2. Read against the actual `main`
source — **where this contradicts the roadmap, this audit wins** (explicit
corrections in §8). No feature code written.

---

## 1. Public API surface (by feature area)

Package: one product, one target `KassiOS` (19 source files), zero dependencies.

**Test lifecycle — `KassTestCase: XCTestCase`**
`app`, `config`, `device`; `launch()`, `launch(deeplink:)`, `launch(stubs:)`,
`relaunch()`; `onScreen(_:_:)`, `step(_:_:)`, `scenario(_:)`,
`parameterized(_:name:_:)`; flow: `flakySafely`, `continuously`, `compose`(+`KassBranch`),
`retry(times:)`, `pressBack`; combinators (`KassCombinators.swift`): `waitForAny`,
`waitForAll`, `assertOnScreen`, `alert()`→`KassAlert`; `assertNoAccessibilityIssues(for:)`
(iOS 17+); structured run: `before`/`after`/`run` (`KassRunBuilder`); `KassSuite`.

**Screens — `KassScreen`**
Builders: `button`/`staticText`/`textField`/`secureTextField`/`image`/`cell`/
`switchControl`/`link`/`other`, generic `element(_:type:)`, `custom`,
`customCollection`; collections `all(_:)`/`all(_:type:)`/`buttons()`/`staticTexts()`/
`cells()`/`images()`; web `webView()`/`links()`; `onLoad`.

**Elements — `KassElement`** (all chainable, self-waiting)
Actions: `tap`, `typeText`, `clearText`, `replaceText`, `doubleTap`, `longPress`,
`swipeUp/Down/Left/Right`, `pinch`/`rotate`/`twoFingerTap` (iOS), `tapAtNormalizedOffset`,
`drag(to:)`, `pullToRefresh`, `scrollTo(in:direction:)`, `setSwitch`,
`adjustSlider`/`adjustPicker` (iOS), `within(timeout:)`, `readValue`/`readLabel`,
scoped children (`descendant` + `button`/`staticText`/…).
Assertions: `assertVisible` (strict/hittable), `assertPresent` (soft/frame),
`assertExists`/`assertNotExists`/`waitUntilGone`, `assertEnabled`/`assertDisabled`,
`assertSelected`, `assertHittable`/`assertNotHittable`, `assertHasText`/`assertHasValue`/
`assertLabel`/`assertLabelContains`/`assertValueMatches`/`assertPlaceholder`,
`waitUntil(_:_:)`; throwing checks for flow: `requireExists`/`requireVisible`/
`requirePresent`/`requireHittable`; escape hatch `perform(_:_:)`.

**Collections — `KassElementCollection`**
`count`, `element(at:)`, `first`/`last`, `containing`/`matching`/`elementMatching`,
`forEach`/`map`, `assertCount`/`assertNotEmpty`.

**Config — `KassConfig`** (value type, flows into every screen/element)
`timeout`, `pollInterval`, `flakySafetyEnabled`, `logger`, `reporter`,
`synchronizer`, `accessibilityIdentifierPolicy` (`.ignore`/`.warn`/`.enforce`),
`captureScreenshotOnFailure`, `screenshotEachStep`. Types: `KassIdentifierPolicy`,
`KassStepStatus`, `KassReporter` (+ no-op `addLabel`/`addLink` defaults),
`KassLogger`/`ConsoleKassLogger`.

**Reporting** — `AllureReporter`, `JUnitReporter`, `KassMetadata` (severity/epic/
feature/story/owner/tag + issue/tms links). **Sync** — `KassSynchronizer`,
`NoOpSynchronizer` (+ opt-in EarlGrey adapter in `Examples/`, not compiled).
**Device — `KassDevice`** — `autoAllowSystemDialogs`, `allowSystemDialogNow`,
`hideKeyboard`, `screenshot`, `attachText`, `sendToBackground`, `foreground`,
`pressHome`, `rotate(to:)`, `open(url:)`, `springboard`, `waitForIdle`.
**Codegen** — `KassScaffold.generate/printScreenScaffold`. **Snapshot** —
`assertSnapshot`, `KassSnapshotResult`. **Docloc** — `forEachLocale`.
**Internals** — `Waiter.retry`, `KassFlow`, `KassError`.

## 2. Flaky-safety mechanism — **retries are INLINED, there is NO interception seam**

`KassElement.perform(_:file:line:_ body:)` is the single choke point every action
and assertion flows through. It hardcodes a fixed pipeline:

```
reporter.stepStarted
  → Waiter.retry(timeout, pollInterval, enabled) {
        synchronizer.waitForIdle(timeout)
        body(resolve())            // re-resolves the element each attempt
    }
  → enforceIdentifierIfNeeded(resolve())     // strict-id post-check
  → reporter.stepFinished(.passed)
catch:
  → failureDiagnostics() + attachFailureScreenshot + reporter.failed + XCTFail
```

`Waiter.retry` (pure, Foundation-only) shares one time budget across attempts
(no compounding). `KassElement` stores a `() -> XCUIElement` closure, not a cached
element — this is the real flaky-safety fix.

**Consequence for Phase 2 sizing:** the *behaviours* the roadmap wants as
interceptors (retry, logging, screenshot-on-failure, Allure step, id-enforce)
already exist — but as a **fixed inline sequence**, not a pluggable chain. Phase 2
is a genuine **refactor of `perform()` into a composable chain**, not "formalize a
partial interceptor" (see §8). Medium size: the pieces are there to extract; the
work is the seam + preserving exact semantics. Collections
(`assertCount`/`assertNotEmpty`) and combinators (`waitForAny`/`waitForAll`) each
call `Waiter.retry` directly and would also need to route through the chain.

## 3. Accessibility-id enforcement — **per-interaction check, NOT a tree audit**

`config.accessibilityIdentifierPolicy` + `KassElement.enforceIdentifierIfNeeded`:
after an element built from an identifier is resolved, it compares the resolved
`element.identifier` to the expected id. Empty/mismatched ⇒ `.warn` (Xcode
message) or `.enforce` (fail). It only checks elements the test *touches*, and
only those built via id builders (`custom` is exempt).

Two adjacent pieces exist: `KassScaffold` walks `descendants(matching:)` and
**counts** elements missing ids (generation aid); `assertNoAccessibilityIssues`
wraps Apple's `performAccessibilityAudit` (iOS 17+).

**For Phase 5:** the roadmap assumes a runtime accessibility-tree walk reporting
*every hittable element lacking an id with screenshot + tree path*. **That does
not exist yet** — today's enforcement is touch-time and per-element. `KassScaffold`
is the seed to build the tree-walk audit from. So Phase 5 "harden" = build the
audit, not sharpen an existing one (see §8).

## 4. Allure export — shape & attachment hooks

`AllureReporter: KassReporter` writes Allure 2 JSON, **one `<uuid>-result.json`
per test** (+ separate `<uuid>-attachment.*` files) into `$ALLURE_RESULTS_PATH`
or `<temp>/allure-results`. `NSLock` + UUID filenames ⇒ safe under parallel
simulator clones. Nested steps via a mutable `StepNode` tree; steps left open by
a hard failure are closed with the test's terminal status. Metadata/links
supported (`addLabel`/`addLink`). `JUnitReporter` mirrors the protocol (one
`<testsuite>` per test under `$KASS_JUNIT_PATH`).

Attachments hook at three points, all via `KassReporter.attach`: `device.screenshot`,
per-step screenshots (`screenshotEachStep`), and `tearDown` on failure
(screenshot **+ full `app.debugDescription` accessibility tree**) — Phase 6 already
has the raw materials, just not a structured JSON artifact.

## 5. Concurrency posture — **greenfield; baseline 442 warnings**

- `swift-tools-version:5.9`. No `swiftLanguageModes`. **No** `@MainActor`/
  `Sendable`/`@unchecked` anywhere in the source.
- `-strict-concurrency=complete` typecheck (iOS): **442 warnings, 0 errors.**
  All are XCUITest main-actor isolation crossings — `exists` (94), `isHittable`
  (26), `tap()` (24), `XCTContext.runActivity` (20), subscript (18), `firstMatch`
  (16), `label`/`count`/`value`, `typeText`, etc. Root cause: `XCUIElement`/
  `XCUIElementQuery`/`XCTContext` are `@MainActor` in the current SDK, and KassiOS
  touches them from nonisolated contexts — notably inside the `Waiter.retry`
  escaping closures.
- This is the single largest Phase 1 item (§2.2). Fixing it means annotating the
  DSL `@MainActor` and reconciling that with `Waiter.retry`'s escaping closure
  (which runs synchronously on the calling actor, so likely `@MainActor`-annotate
  the closure param rather than `@unchecked Sendable`). **Baseline to drive to 0.**

## 6. Platform support

`Package.swift` declares `.iOS(.v14)`, `.macOS(.v11)`. Both **build** (unit tests
run on macOS; UI tests on iOS Simulator in CI). visionOS/tvOS/watchOS are **not
declared** and untested. iOS-only APIs (`pinch`/`rotate`/`pressHome`/`open(url:)`/
`adjustSlider`) are correctly `#if os(iOS)`-guarded. Stale comment in
`Package.swift` calls the module a "placeholder name — rename" — should be removed.

## 7. Test coverage of the package itself

- **9 unit-test files**, all pure-logic (Foundation only): `WaiterTests`,
  `KassFlowTests`, `KassParameterizedTests`, `KassRunTests`, `KassScaffoldTests`
  (camelCase), `KassSnapshotTests` (pixel engine), `KassTestCaseTests`
  (name parsing), `AllureReporterTests`, `JUnitReporterTests`. Run on `platform=macOS`.
- **DSL behaviour** (interactions, asserts, gestures, collections, strict-id,
  a11y audit, scaffold, localized, pull-to-refresh) is covered by
  `IntegrationTests/` — a bundled SwiftUI demo app + 10 KassiOS UI tests run on
  the simulator in CI (project generated by `ruby gen.rb`).
- **Gaps:** individual assertions/gestures have no dedicated unit tests (covered
  transitively by integration); no test exercises `assertSnapshot` end-to-end on a
  device (deliberately — pixel refs are device-pinned); no strict-concurrency gate.

---

## 8. Roadmap reconciliation — implemented / partial / greenfield (audit wins)

**Corrections to §0.5 parity table & phase assumptions:**

| Roadmap claim | Reality | Verdict |
|---|---|---|
| "Interceptor mechanism: partial → formalize" | No chain exists; fixed inline pipeline in `perform()`. Behaviours exist to extract. | **Refute "partial"** — Phase 2 is a real refactor, not formalizing an existing chain. |
| "Close system dialogs: **GAP**" | `device.autoAllowSystemDialogs` + `allowSystemDialogNow` exist (interruption monitor + springboard). | **Refute GAP** — partial (no per-type policy, not an interceptor). |
| "pull-to-refresh: **GAP** (hand-written)" | `KassElement.pullToRefresh()` exists. | **Refute** — implemented (harden/document). |
| "Auto-scroll to element: have/partial" | Only manual `scrollTo(in:)`; no auto-scroll-before-interact. | **Confirm partial.** |
| "Re-run failed actions: have (verify)" | Yes — `Waiter` (per-interaction, time budget) + `retry(times:)` + CI `-retry-tests-on-failure`. Not a `RetryInterceptor`. | **Confirm.** |
| Phase 5 "walks the accessibility tree at runtime… keep it" | Enforcement is **per-interaction**, not a tree walk. `KassScaffold` counts missing ids. | **Refute** — the tree audit is greenfield; build it. |
| Phase 1 "Documentation: ✗ none" | DocC catalog + hosted on GitHub Pages + `.spi.yml` all present. SPI signal is ✗ only because not indexed yet (PackageList PR #14381 pending). | **Refute** — Phase 1 docs largely done; SPI flips on index. |
| `disableAnimations` "config" | Absent. | **Confirm greenfield.** |

**Phase-by-phase status:**
- **Phase 1 — mostly DONE.** ✅ DocC + `.spi.yml`, Migration guide, README "How it
  compares", parameterized tests (implemented — needs the "Swift Testing can't do
  UI" positioning stated louder), CHANGELOG/compare-links. **Remaining (real work):**
  Swift 6 strict concurrency (442→0), keywords (`automation`/`xcui-testing`),
  "Coming from Kaspresso" + "Why your XCUITest flakes" + "CI recipe" docs, SPI
  compat badges.
- **Phase 2 — greenfield architecture, existing behaviours.** Extract `perform()`
  into an interceptor chain; lift retry/logging/screenshot/Allure/id-check into
  built-ins; `SystemAlertInterceptor` (wrap existing dialog handling as a policy);
  new: `disableAnimations`, auto-scroll-before-interact. Route collections +
  combinators through the chain too.
- **Phase 3 — partial.** `Scripts/kass-simctl.sh` (host-side simctl) exists; Tier
  A/B partially via `KassDevice` (`rotate`, `pressHome`, `open(url:)`,
  `sendToBackground`) + launch env. **Greenfield:** in-test `device` DSL, the
  `kassios-agent` executable product, localhost bridge, UDID targeting, auth.
- **Phase 4 — greenfield.** `launch(stubs:)` is only an env convention (app-side).
  No `URLProtocol` stub bridge / `KassiOSStubs` product / mock server.
- **Phase 5 — enforcement exists, audit greenfield.** Per-element policy done;
  tree-walk audit + allowlist + severity + attachment: build. Static SwiftSyntax
  plugin: greenfield separate package.
- **Phase 6 — raw materials exist, artifact greenfield.** Failure diagnostics
  (element snapshot + screenshot + a11y tree) exist; structured JSON artifact +
  flaky detection/quarantine: build (falls out of Phase 2's chain).
- **Phase 7 — partial.** `onScreen` + `onLoad` give page-load verification via
  existence; typed fluent navigation returning the landing screen: greenfield.

## 9. Recommended sequencing (unchanged from roadmap, with one note)

Phase 1 (finish: **strict concurrency is the load-bearing item**, docs mostly done)
→ Phase 2 (the seam, blocking) → 3–6. Phase 7 any time. Keep core zero-dep; agent
(Phase 3), stub bridge (Phase 4), SwiftSyntax plugin (Phase 5.2) each go in their
own product/package.

**One recommendation:** do a small **Phase 1a** first — remove the stale
Package.swift comment, add keywords, and land the strict-concurrency pass as its
own release (`0.10.1`), since it's mechanical and unblocks a clean Swift-6 story
before the Phase 2 refactor churns the same files.
