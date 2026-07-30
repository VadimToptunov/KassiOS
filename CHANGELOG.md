# Changelog

All notable changes to KassiOS are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Soft assertions (1.3.0) — additive, non-breaking.**
  - `KassTestCase.verifyAll(_:file:line:_:)` — the standard QA "soft
    assertion"/"verify-all" pattern for a screen-state check: runs `block`
    with `continueAfterFailure` enabled for its scope, so every KassiOS
    assertion inside still records its failure but the block runs to the
    end — one run reports *all* the mismatches on a screen instead of
    stopping at the first. Restores the prior `continueAfterFailure` setting
    afterward and groups the checks under a named step in the report. The
    whole-screen counterpart to `KassElementCollection.assertEach(_:_:)`,
    which is the same soft-aggregate idea scoped to a collection's rows.

## [1.2.0] - 2026-07-29

### Added
- **Clearer flow-primitive names (1.2.0) — additive readability renames, no
  breaking changes.**
  - `KassTestCase.eventually(timeout:pollInterval:file:line:_:)` — a
    clearer-named twin of `flakySafely(...)` (same "retry until it stops
    throwing or the budget elapses" behavior; the new name reads as the
    classic "eventually this passes" without borrowing the word "flaky").
  - `KassTestCase.anyOf(file:line:_:)` — a clearer-named twin of `compose(...)`
    (same "pass if at least one `KassBranch` succeeds" behavior; the new name
    says what the check does instead of what it's built from).
  - `KassDevice.pressBack(file:line:)` — device-level navigation now lives
    next to `device.pressHome()` instead of on `KassTestCase` (same "tap the
    leading navigation-bar button" behavior).

### Deprecated
- `KassTestCase.flakySafely(...)` → use `eventually(...)`.
- `KassTestCase.compose(...)` → use `anyOf(...)`.
- `KassTestCase.pressBack(...)` → use `device.pressBack(...)`.
  All three deprecated methods still work identically (thin forwarders); they
  are kept for source compatibility and will not be removed before the next
  major version.

## [1.1.0] - 2026-07-29

### Added
- **API ergonomics — additive readability smoothing, no breaking changes.**
  - `KassElement.assertTextContains(_:)` — a clearer-named twin of
    `assertHasText(_:)` (same substring-of-value-or-label behavior; the old
    name read like an exact match, confusable with the exact `assertHasValue`).
  - `KassElement.toggle()` — flips a switch unconditionally, complementing
    `setSwitch(on:)` (which only taps when the state differs).
  - `KassScreen.button(containing:)` — the button counterpart of
    `staticText(containing:)`, for resolving a button by a label substring.

### Deprecated
- `KassElement.assertHasText(_:)` → use `assertTextContains(_:)`.
- `KassElementCollection.elementMatching(label:)` → use `matching(label:).first`.
  Both deprecated methods still work identically; they're kept for source
  compatibility and will not be removed before the next major version.

## [1.0.0] - 2026-07-28

### Stabilized
- **First stable release — the public API is now frozen under semantic
  versioning.** KassiOS has been dogfooded against two real apps (a fintech app
  and a game) and a buggy-matrix suite that catches planted defects, which drove
  six evidence-based releases (0.21–0.26). The whole public surface — screen /
  robot / scenario objects, id-first locators, deep assertions, the device tiers,
  snapshot / localization / video, the `kassios-lint` plugin, and agent-discovery
  (did-you-mean + identifier inventory) — is considered stable. Breaking changes
  will bump the major version from here.

## [0.26.0] - 2026-07-28

### Added
- **"Did you mean?" suggestions on a not-found failure** — when a locator's
  target has an `expectedIdentifier` and it genuinely doesn't exist, the
  failure message now walks the current screen once (bounded to 400 elements)
  and appends the closest actual identifiers/labels on screen, ranked by
  case-insensitive Levenshtein distance: `↳ did you mean: 'welcome',
  'Welcome!'?`. Lets a wrong-id guess (common from an AI author) self-correct
  without a second round trip. New pure, unit-tested API:
  `KassIdentifierSuggestions.nearest(to:among:max:maxDistance:)`. Gated behind
  a new `KassConfig.suggestSimilarIdentifiersOnFailure` flag (default `true` —
  the walk only runs once an assertion has already failed). Wired into
  `KassElement.perform`, `scrollTo` and `softScrollTo`.
- **`device.dumpIdentifiers(includingUnidentified:)` / `attachIdentifierInventory(includingUnidentified:)`**
  — an agent-facing inventory of the current screen: every element's
  `{ identifier, type, label, isHittable }` as `Codable` `KassIdentifierInfo`
  values, feeding a coding agent's screen-object scaffold or a discovery pass.
  Bounded to the same 400-element walk as the suggestions above; `attach…`
  additionally attaches the inventory as pretty-printed, sorted-key JSON to
  the report.

## [0.25.0] - 2026-07-28

### Added
- **`kassios-lint` base-class tracing** — `inheritsKassScreen` (and the
  equivalent check for `KassTestCase`/`KassRobot`) now resolves any number of
  hierarchy levels, computed as a fixpoint over every class declared in the
  linted file set, so `final class HomeScreen: CBScreen` is recognized even
  when `CBScreen: KassScreen` lives in another file. A new batch entry point,
  `lint(sources:)`, lints every file together so cross-file bases resolve; the
  CLI (`kassios-lint`) now calls it once over every collected file instead of
  linting file-by-file. `lint(source:filePath:)` still works for a single file
  (only same-file bases resolve there).
- **KAS003 — actions outside a Robot.** A new conservative rule: a
  `KassTestCase` subclass's test method with 5+ inline element interactions
  (`tap`, `typeText`, `swipeUp`, …) gets a warning nudging toward extracting a
  reusable `KassRobot`. Never fires inside a `KassRobot` subclass's own
  methods.
- **`// kassios:ignore-id` suppression for KAS002** — a real trailing comment
  (found via the parsed comment trivia, not raw line text) on a flagged
  builder call's own line suppresses that finding, for a reviewed,
  deliberately dynamic identifier. The same phrase sitting inside a
  string-literal argument on that line does *not* suppress anything — only an
  actual comment counts.

## [0.24.0] - 2026-07-28

### Added
- **`KassElement.assertValue(closeTo:tolerance:)` / `readNumber()`** — a
  locale-aware numeric assertion for money/math, where an exact string match
  is the wrong tool (rounding, formatting, and locale can all shift the
  displayed text without the underlying value being wrong). `readNumber()`
  parses via `NumberFormatter` (`.decimal` then `.currency`) and falls back to
  stripping non-numeric characters when neither style matches.
- **`KassElement.assertAppears(within:pollInterval:)`** — a fast-polling
  existence check for transients (a success toast that shows then
  auto-dismisses). Unlike `assertVisible`, which waits the full flaky-safety
  budget for the element to be hittable *now*, this passes the instant the
  element is first sighted and deliberately bypasses `Waiter`.
- **`KassElementCollection.assertNoDuplicates(by:)`** — fails if two elements
  share a key (default: label), catching duplicated rows from pagination bugs.
  The underlying duplicate-finding is factored into
  `KassElementCollection.duplicates(in:)` for unit testing.
- **`KassElementCollection.assertEach(_:_:)`** — runs a check against every
  matching element and aggregates *all* failures (not just the first) into one
  message, catching e.g. a row that leaked into a filtered list.
- **`KassElementCollection.within(timeout:pollInterval:)`** — a per-call
  timeout override for collections, mirroring `KassElement.within(timeout:)`.
  Useful for a one-off short budget on a collection assertion expected to fail
  (e.g. asserting no duplicates against a known-broken state in a test).

  These three were driven directly by a buggy-matrix experiment against
  ChaosBank: presence-only assertions (`assertVisible`/`assertCount`) missed
  `roundingDrift`, `paginationDup`, `filterLeaksCategory`, and
  `successToastMissing` — each needs a numeric, dedup/per-row, or transient
  check to catch, not another exists-check.

## [0.23.0] - 2026-07-28

### Added
- **`KassScreen.element(_ id:)`** — resolves by accessibility identifier
  regardless of element type. SwiftUI exposes the same view as button/cell/other
  depending on context, and pinning a type to a locator was the single most
  common source of flake reported against real suites (`anyEl`-style helpers
  appeared 51 times across surveyed test suites).
- **`element(id:label:type:)` / `button(id:label:)`** — matches an element
  carrying *both* an accessibility identifier and a label, for SwiftUI's
  container-id propagation (a sheet's id landing on every child).
- **`staticText(containing:)` / `element(labelContains:type:)`** — matches a
  label substring (case-insensitive) for dialogs/toasts/rows identified only by
  their text. Intentional label matching: it carries no expected identifier, so
  it never triggers the identifier-policy warning.
- **`KassTestCase.onScreen(_:timeout:_:)`** — a per-scope timeout override: runs
  a screen's `onLoad` check and block with a one-off time budget (e.g. a slow
  web view or network-bound screen) without repeating `.within(timeout:)` on
  every element in it.

### Changed
- **Identifier resolution is now id-first.** `element(_:type:)` and
  `descendant(_:_:)` used to resolve via XCUITest's `[id]` subscript, which
  silently falls back to matching an element's *label* when its accessibility
  identifier is empty — so a test author could think they matched by id while
  actually matching a label. Both now match the real identifier first and only
  fall back to the label subscript when no element carries that identifier.
  Non-breaking: existing tests still resolve the same elements, they just get
  an honest signal when a fallback happens.
- **`KassConfig.accessibilityIdentifierPolicy` default changed from `.ignore` to
  `.warn`.** Combined with id-first resolution above, a label-fallback match is
  no longer silent by default — it logs a warning (`.enforce` still fails,
  `.ignore` still mutes). Not breaking on its own: a suite whose elements
  resolve by real identifiers (the documented convention) sees no new warnings;
  one that relies on label-fallback now finds out about it.

## [0.22.0] - 2026-07-22

### Changed
- **Accessibility-identifier convention documented + examples reconciled.** A new
  DocC guide *Accessibility identifiers* states the one convention KassiOS matches
  on — **dot.camelCase, hierarchical** (`login.email`, `markets.asset.AAPL.price`)
  — and the `Examples/` screens + README snippets, which mixed `snake_case`, are
  brought in line so the docs teach a single scheme.
- **`kassios-lint` KAS002 no longer false-flags parameterized identifiers.** It
  now fires only when an element id isn't a string literal at all (a bare
  variable or call); **interpolated literals** like `"markets.asset.\(symbol).price"`
  pass (they still reveal the id's structure) — so the lint is usable on real
  list screens.

## [0.21.0] - 2026-07-22

### Added
- **`KassRobot` — a first-class Robot layer**: an optional base class for
  composite, cross-screen actions ("sign in", "transfer") that sits between
  ``KassScreen`` (locators) and ``KassScenario`` (whole journeys), replacing the
  hand-rolled `struct XRobot { let test: KassTestCase }` boilerplate every
  project used to write. Enter one with the new `KassTestCase.robot(_:)`, e.g.
  `robot(LoginRobot.self).signIn("a@b.c").welcome.assertVisible()`. Fully
  opt-in — single-screen tests keep using `onScreen` directly.

## [0.20.0] - 2026-07-22

### Added
- **Screen recording on failure**: opt in with `KassConfig(recordVideoOnFailure:
  true)` and, when the Tier C host agent is reachable, KassiOS records the
  simulator screen for the test and attaches the `.mp4` to the report **only if
  the test fails** (a passing test discards it). Also exposed directly as
  `device.startRecording()` / `device.stopRecording() -> Data?`. New agent
  commands `startRecording`/`stopRecording` drive `simctl io recordVideo` and
  return the bytes over the loopback bridge — the agent picks the output path
  itself, preserving the fixed-argv, allowlisted posture. Best-effort and
  simulator-only: no agent (or a real device) is a silent no-op, never a hang.

### Fixed
- **Relaunch no longer accumulates launch arguments.** Every `launch`/`relaunch`
  now composes its arguments against a stable base (captured on the first launch)
  instead of appending to the shared `XCUIApplication.launchArguments`, so mixing
  `forEachLocale`, `runPseudolocalized`, and `device.relaunch` in one test no
  longer silently inherits a prior run's locale. `KassDevice.relaunch` shares the
  test case's base rather than tracking its own.

## [0.19.0] - 2026-07-22

### Added
- **Pseudolocalization & RTL**: `KassTestCase.runPseudolocalized(rightToLeft:)`
  relaunches with doubled localized-string lengths and uppercased non-localized
  strings, then runs your flow — surfacing truncation/overflow and hardcoded
  strings without a translator. New `KassLaunchOptions` toggles
  `doubleLengthStrings()`, `showNonLocalizedStrings()`, and `rightToLeft()` map
  to the standard Apple debug-language launch arguments, so they compose with a
  real `locale()`/`language()` and work on simulator and real devices.

## [0.18.0] - 2026-07-22

### Added
- **Snapshot diff & masking**: on a snapshot mismatch KassiOS now attaches a
  triptych — the reference, the actual, and a generated **diff** image (unchanged
  UI dimmed to grayscale, changed pixels flagged red) — instead of just the
  failing image, so you can see *what* moved from the `.xcresult`. New
  `assertSnapshot(..., ignoring: [CGRect])` masks normalized (0...1) regions out
  of both images before comparing, to neutralize dynamic content (a status-bar
  clock, a timestamp). Still zero-dependency (ImageIO/CoreGraphics).

## [0.17.0] - 2026-07-21

### Added
- **Static lint** (Phase 5.2): `kassios-lint`, a SwiftSyntax-based linter that
  statically twins the runtime `auditAccessibilityIdentifiers()` audit. It
  flags `KassScreen` subclasses with no non-empty `onLoad` (KAS001) and
  element-builder calls whose identifier isn't a static string literal
  (KAS002). Lives in a **nested** package at `Plugins/` (an SPM command
  plugin, `swift package kassios-lint`) so swift-syntax never becomes a
  dependency of the core `KassiOS` library — the root manifest is untouched.

## [0.16.0] - 2026-07-21

### Added
- **Typed, fluent navigation** (Phase 7): `KassScreen.navigate(to:)` asserts the
  landing screen's `onLoad` (its "I have arrived" condition) and returns it, so a
  multi-screen test reads as a route and fails fast when it doesn't land where
  expected — `onScreen(A) { … }.navigate(to: B.self).someElement`. Opt-in:
  one-screen tests stay one screen simple. New DocC guide *Typed navigation & the
  Robot pattern*.

## [0.15.0] - 2026-07-21

### Added
- **Agent-readable diagnostics** (Phase 6): a failed element interaction (a
  `perform`-backed action or a scroll) now attaches a structured `KassDiagnostic`
  JSON artifact (the action + kind, the resolved element's live state incl. a
  structured frame, expected identifier, error, source location, active
  interceptors, timeout/flaky-safety) to the `.xcresult` and the structured
  report — designed to be handed straight to a coding agent rather than parsed
  out of xcresult after the fact.
- **Flaky detection** (Phase 6): the retry interceptor records actions that
  passed only *after* a retry into a `KassFlakyTracker`; at teardown a green test
  that recovered attaches a machine-readable `[KassFlakyRecovery]` report — a
  quarantine signal that falls out of the interceptor chain for free.

## [0.14.0] - 2026-07-21

### Added
- **Accessibility audit** (Phase 5): `auditAccessibilityIdentifiers()` proactively
  scans the current screen for **hittable, interactive** elements missing an
  accessibility identifier — the ones only reachable by brittle label text —
  reporting each (with a screenshot + report attachment). Configurable
  `severity` (`.warn` / `.fail`) and an allowlist for legitimately-unlabelled
  (decorative / system) elements. Complements the existing per-element
  `.enforce` policy, which only fires on elements a test actually uses.

## [0.13.0] - 2026-07-21

### Added
- **Network control** (Phase 4): the in-app stub bridge. A new `KassiOSStubs`
  product the app links in debug and installs at launch
  (`KassiOSStubs.installIfConfigured()`); the test drives it with
  `launch(networkStubs: [.json(urlContains:body:)])` or `launch(offline: true)`. A
  `URLProtocol` replays matching requests (or fails them with
  `URLError.notConnectedToInternet`) — no server, no ports, deterministic, works
  on simulator and real devices.

## [0.12.0] - 2026-07-20

### Added
- **Device control Tier B** (Phase 3): `device.relaunch { $0.locale("de_DE") }`
  — a `KassLaunchOptions` builder (locale / language / Dynamic Type) applied as
  launch arguments. No host bridge; works on simulator and real devices, modelled
  honestly as a relaunch.
- **Device control Tier C** (Phase 3): the `kassios-agent` executable — a
  127.0.0.1-only, token-authenticated host bridge that shells out to an
  allowlisted `simctl` command set. New DSL `device.permissions.grant(_:for:)`,
  `device.statusBar.freeze(...)`, `device.location.set(...)`, `device.push(...)`,
  `device.appearance(_:)` — each keyed by `SIMULATOR_UDID` (parallel-safe) and
  `XCTSkip`ping (never hanging) when no agent is reachable or on a real device.

## [0.11.0] - 2026-07-20

### Added
- **Interceptor core** (Phase 2): a pluggable chain every waiting DSL action
  flows through (`KassConfig.interceptors`). `KassInterceptor` +
  `KassActionContext`/`KassActionKind`, with the built-in flaky-safety lifted
  into a reorderable `KassRetryInterceptor` (position an interceptor before it to
  run once, after it to run per attempt). Behaviour-preserving: the default
  `[KassRetryInterceptor()]` matches the previous inline retry exactly.
- Built-in interceptors: `KassLoggingInterceptor` (per-action log) and
  `KassSystemAlertInterceptor` (auto-accept/dismiss iOS permission dialogs —
  location, notifications, tracking, …).
- `KassElement.softScrollTo(in:direction:)` — a gentle, short press-drag that
  reaches small off-screen rows without `swipeUp`'s momentum overshoot.
- `KassConfig.disableAnimations` (opt-in) — sets `KASS_DISABLE_ANIMATIONS=1` in
  the launch environment for the app to honour, for faster, steadier runs.

## [0.10.1] - 2026-07-19

### Changed
- Adopted the Swift 6 language mode (`swift-tools-version:6.0`,
  `swiftLanguageMode(.v6)` on both targets) and drove
  `-strict-concurrency=complete` from 442 warnings to zero. The DSL is
  annotated `@MainActor` throughout: `KassTestCase` is `@MainActor` at the class
  level, so **your test subclasses inherit the isolation with no annotation of
  your own** (`setUp()`/`tearDown()` stay `nonisolated` to match XCTestCase;
  `config` is `nonisolated(unsafe)` so it's still assignable in `setUp`). Also
  `KassElement`, `KassElementCollection`, `KassScreen`, `KassDevice`, `KassAlert`,
  `KassRunBuilder`, `KassSuite`, `KassScaffold`; `Waiter.retry` and `KassFlow`'s
  static functions now take `@MainActor` action closures. No behavior change —
  same runtime semantics, only concurrency annotations and the `Package.swift`
  bump. Removed the stale "placeholder name" comment from `Package.swift`.
- `KassLogger`, `KassReporter`, `KassSynchronizer`/`NoOpSynchronizer`, and
  `KassConfig` are now `Sendable`. `AllureReporter`/`JUnitReporter` are
  `@unchecked Sendable` (justified: all mutable state is guarded by an
  `NSLock`). New internal `MainActorBox` bridges a handful of `@MainActor`
  closures/`self` references across Sendable-requiring boundaries
  (`XCTestCase.addTeardownBlock`, and `setUp`/`tearDown` overriding
  XCTestCase's nonisolated Objective-C lifecycle hooks).

### Added
- Documentation: DocC guides — *Coming from Kaspresso*, *Why your XCUITest suite
  flakes*, *Parameterized UI tests*, and *Running KassiOS on CI* — plus a README
  positioning rewrite (leads with "Swift Testing doesn't do UI testing" and "a
  suite, not a helper", with a *Where Swift Testing fits* table) and Swift Package
  Index swift-versions/platforms badges.

### Fixed
- Integration suite: `test_webView` no longer flakes — it now enters the home
  scope before tapping the `NavigationLink`, instead of racing the login→home
  transition.

## [0.10.0] - 2026-07-12

### Changed
- `assertVisible` is now strict (`exists && isHittable`), so it can't go falsely
  green on an off-screen element; the previous frame-based soft check moved to a
  new `assertPresent` (and `requirePresent`). `onScreen`/`assertOnScreen` now
  check `onLoad` elements for existence rather than visibility.
- The synchronizer's `waitForIdle` now runs in collection assertions
  (`assertCount`/`assertNotEmpty`) and `waitForAny`/`waitForAll`, not just
  interactions — so a real backend (EarlGrey) applies everywhere.

### Added
- `KassTestCase.launch(deeplink:)` — the reliable launch-argument deep-link
  convention (`device.open(url:)` via Safari is now documented as a fallback).
- Snapshot references honour `$KASS_SNAPSHOTS_PATH` (for CI) instead of only the
  `#file`-adjacent folder.
- `JUnitReporter` — a `KassReporter` that writes JUnit XML (one file per test
  under `$KASS_JUNIT_PATH`) for CI systems that don't speak Allure.
- `KassTestCase.launch(stubs:)` — network-stub launch convention
  (`KASS_STUB_<name>` env the app reads to serve fixtures).
- A failing test now also attaches the full accessibility tree
  (`app.debugDescription`) in `tearDown`.
- Community & discovery: `.spi.yml` (Swift Package Index build/docs),
  `CONTRIBUTING.md`, issue/PR templates, and a "How it compares" table in the
  README (KassiOS vs raw XCUITest vs EarlGrey).

### Fixed
- `KassSuite` docstring used a non-existent `requireAccessibilityIdentifiers`
  parameter; corrected to `accessibilityIdentifierPolicy: .enforce`.
- Documented `clearText`/`replaceText`'s delete-by-length limitation on
  secure/formatted fields.

## [0.9.0] - 2026-07-10

### Added
- WebView support: `KassScreen.webView()`, `link(_:)`, `links()`.
- Wait-combinators `waitForAny` / `waitForAll` / `assertOnScreen`, and an app-alert
  DSL `alert().assertExists().tap("OK")`.
- `KassScaffold` — generate `KassScreen` objects from the live accessibility tree
  (and count elements missing an identifier).
- `forEachLocale` — localized screenshot runs (Docloc-style).
- Allure metadata: `severity`, `epic` / `feature` / `story`, `owner`, `tag`, plus
  issue / tms / custom links.
- `config.screenshotEachStep` (a screenshot after every `step`) and
  `device.attachText` for arbitrary text attachments.
- `KassElement.pullToRefresh()`.
- `Scripts/kass-simctl.sh` — host-side CI helpers (permissions, location, push,
  clean status bar, appearance, deep link, reset).
- Documentation: [migration guide](Documentation/Migration.md); README badges.

### Changed
- CI now runs three jobs — SwiftLint, unit tests (macOS), and UI tests
  (simulator) with `-retry-tests-on-failure` and a Pro-simulator preference —
  plus a DocC → GitHub Pages workflow. Added a `.swiftlint.yml` and fixed all
  lint violations.

## [0.8.0] - 2026-07-10

### Added
- Accessibility-identifier policy `.ignore` / `.warn` / `.enforce`
  (`KassConfig.accessibilityIdentifierPolicy`). `.warn` surfaces an Xcode message
  without failing; `.enforce` fails when an element is matched by label instead
  of a real `accessibilityIdentifier`.
- Accessibility audit: `assertNoAccessibilityIssues(for:)` wrapping
  `performAccessibilityAudit` (iOS 17+).
- Per-call configuration `KassElement.within(timeout:pollInterval:)`.
- Element reads and actions: `readValue`, `readLabel`, `assertPlaceholder`,
  `tapAtNormalizedOffset(x:y:)`, `drag(to:)`.
- Bundled `IntegrationTests/`: a SwiftUI demo app plus KassiOS-driven UI tests
  that run on the simulator; wired into CI as a second job.

### Changed
- `KassRunBuilder.after` now runs via `addTeardownBlock`, so it executes even
  after a hard failure.
- Replaced `KassConfig.requireAccessibilityIdentifiers: Bool` with the
  `accessibilityIdentifierPolicy` enum.

### Fixed
- `assertHasText` / `assertValueMatches` now fall back to `label` when `value`
  is an empty string (e.g. SwiftUI `Text`).
- `setSwitch` taps the inner switch control, so it toggles SwiftUI `Toggle`s.

## [0.7.0] - 2026-07-09

### Added
- Strict accessibility-identifier mode and precise failure diagnostics (element
  snapshot + screenshot at the moment of failure).
- `KassSuite` (shared per-suite configuration) and structured
  `before` / `after` / `run`.

## [0.6.0] - 2026-07-09

### Added
- `KassElementCollection` for lists and tables, with `KassScreen` builders.
- Scoped child elements (`descendant` and convenience wrappers).
- Slider / switch / picker controls, `assertLabelContains`, `assertValueMatches`,
  `waitUntil`.
- Parameterized (data-driven) tests via `KassTestCase.parameterized`.

## [0.5.0] - 2026-07-09

### Added
- Kaspresso-style flow primitives: `flakySafely`, `continuously`, `compose`,
  `retry`, `pressBack`, plus throwing `require*` checks.
- Multitouch gestures (`pinch`, `rotate`, `twoFingerTap`) and more device helpers
  (`pressHome`, `springboard`, `allowSystemDialogNow`, `waitForIdle`).

## [0.4.0] - 2026-07-09

### Added
- Pluggable synchronization backend (`KassSynchronizer`, `NoOpSynchronizer`) with
  an opt-in EarlGrey adapter reference.

## [0.3.0] - 2026-07-09

### Added
- Allure 2 report export (`AllureReporter`, `KassReporter`) with nested steps and
  screenshot attachments.

## [0.2.0] - 2026-07-09

### Added
- Gestures and `scrollTo`, richer assertions, `KassDevice` helpers, and reusable
  `KassScenario` flows.

### Fixed
- Elements resolve via `firstMatch`, avoiding "multiple matching elements" crashes
  on ambiguous identifiers.

## [0.1.0] - 2026-07-09

### Added
- Initial DSL: `KassTestCase`, `KassScreen`, `KassElement`, implicit waits,
  flaky-safety (`Waiter`), step logging, and `onScreen`.

[Unreleased]: https://github.com/VadimToptunov/KassiOS/compare/1.2.0...HEAD
[1.2.0]: https://github.com/VadimToptunov/KassiOS/compare/1.1.0...1.2.0
[1.1.0]: https://github.com/VadimToptunov/KassiOS/compare/1.0.0...1.1.0
[1.0.0]: https://github.com/VadimToptunov/KassiOS/compare/0.26.0...1.0.0
[0.26.0]: https://github.com/VadimToptunov/KassiOS/compare/0.25.0...0.26.0
[0.25.0]: https://github.com/VadimToptunov/KassiOS/compare/0.24.0...0.25.0
[0.24.0]: https://github.com/VadimToptunov/KassiOS/compare/0.23.0...0.24.0
[0.23.0]: https://github.com/VadimToptunov/KassiOS/compare/0.22.0...0.23.0
[0.22.0]: https://github.com/VadimToptunov/KassiOS/compare/0.21.0...0.22.0
[0.21.0]: https://github.com/VadimToptunov/KassiOS/compare/0.20.0...0.21.0
[0.20.0]: https://github.com/VadimToptunov/KassiOS/compare/0.19.0...0.20.0
[0.19.0]: https://github.com/VadimToptunov/KassiOS/compare/0.18.0...0.19.0
[0.18.0]: https://github.com/VadimToptunov/KassiOS/compare/0.17.0...0.18.0
[0.17.0]: https://github.com/VadimToptunov/KassiOS/compare/0.16.0...0.17.0
[0.16.0]: https://github.com/VadimToptunov/KassiOS/compare/0.15.0...0.16.0
[0.15.0]: https://github.com/VadimToptunov/KassiOS/compare/0.14.0...0.15.0
[0.14.0]: https://github.com/VadimToptunov/KassiOS/compare/0.13.0...0.14.0
[0.13.0]: https://github.com/VadimToptunov/KassiOS/compare/0.12.0...0.13.0
[0.12.0]: https://github.com/VadimToptunov/KassiOS/compare/0.11.0...0.12.0
[0.11.0]: https://github.com/VadimToptunov/KassiOS/compare/0.10.1...0.11.0
[0.10.1]: https://github.com/VadimToptunov/KassiOS/compare/0.10.0...0.10.1
[0.10.0]: https://github.com/VadimToptunov/KassiOS/compare/0.9.0...0.10.0
[0.9.0]: https://github.com/VadimToptunov/KassiOS/compare/0.8.0...0.9.0
[0.8.0]: https://github.com/VadimToptunov/KassiOS/compare/0.7.0...0.8.0
[0.7.0]: https://github.com/VadimToptunov/KassiOS/compare/0.6.0...0.7.0
[0.6.0]: https://github.com/VadimToptunov/KassiOS/compare/0.5.0...0.6.0
[0.5.0]: https://github.com/VadimToptunov/KassiOS/compare/0.4.0...0.5.0
[0.4.0]: https://github.com/VadimToptunov/KassiOS/compare/0.3.0...0.4.0
[0.3.0]: https://github.com/VadimToptunov/KassiOS/compare/0.2.0...0.3.0
[0.2.0]: https://github.com/VadimToptunov/KassiOS/compare/0.1.0...0.2.0
[0.1.0]: https://github.com/VadimToptunov/KassiOS/releases/tag/0.1.0
