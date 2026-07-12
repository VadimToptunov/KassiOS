# Changelog

All notable changes to KassiOS are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
- Automation: a `CLAUDE.md` project guide, three Claude Code subagents
  (`swift-builder`, read-only `kass-reviewer`, `test-runner`), a `/ship` command
  that chains them, and opt-in `claude-code-action` workflows for PR review and
  `@claude` — see [Documentation/Automation.md](Documentation/Automation.md).
- `JUnitReporter` — a `KassReporter` that writes JUnit XML (one file per test
  under `$KASS_JUNIT_PATH`) for CI systems that don't speak Allure.
- `KassTestCase.launch(stubs:)` — network-stub launch convention
  (`KASS_STUB_<name>` env the app reads to serve fixtures).
- A failing test now also attaches the full accessibility tree
  (`app.debugDescription`) in `tearDown`.

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

[0.9.0]: https://github.com/VadimToptunov/KassiOS/releases/tag/0.9.0
[0.8.0]: https://github.com/VadimToptunov/KassiOS/releases/tag/0.8.0
[0.7.0]: https://github.com/VadimToptunov/KassiOS/releases/tag/0.7.0
[0.6.0]: https://github.com/VadimToptunov/KassiOS/releases/tag/0.6.0
[0.5.0]: https://github.com/VadimToptunov/KassiOS/releases/tag/0.5.0
[0.4.0]: https://github.com/VadimToptunov/KassiOS/releases/tag/0.4.0
[0.3.0]: https://github.com/VadimToptunov/KassiOS/releases/tag/0.3.0
[0.2.0]: https://github.com/VadimToptunov/KassiOS/releases/tag/0.2.0
[0.1.0]: https://github.com/VadimToptunov/KassiOS/releases/tag/0.1.0
