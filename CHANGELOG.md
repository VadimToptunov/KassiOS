# Changelog

All notable changes to KassiOS are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/VadimToptunov/KassiOS/compare/0.15.0...HEAD
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
