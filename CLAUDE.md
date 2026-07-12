# KassiOS — project guide for AI agents

KassiOS is a Kaspresso-style DSL over **XCUITest** (readable screen objects,
implicit waits, flaky-safety), with **zero external dependencies**.

## Build & test

The library wraps XCUITest, so it builds with **Xcode**, not bare `swift build`.
Command Line Tools are usually active, so point at the full Xcode first:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

- **Unit tests** (pure logic, fast): `xcodebuild test -scheme KassiOS -destination 'platform=macOS'`
- **Integration UI tests** (real app on the simulator):
  `cd IntegrationTests && ruby gen.rb && xcodebuild test -scheme KassDemoUITests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath ./DD`
  (`gen.rb` regenerates the demo Xcode project; the KassiOS sources are compiled
  directly into the UI-test target.)
- **Lint**: `swiftlint lint --strict` (config in `.swiftlint.yml`; needs `DEVELOPER_DIR`).
- **Typecheck a single platform** without a full build: `xcrun --sdk iphoneos swiftc -typecheck …` against `Sources/KassiOS/*.swift`.

## Conventions

- Types use the `Kass` prefix. Public API carries `///` doc comments.
- **Zero dependencies** in the core — do not add SPM dependencies. Prefer system
  frameworks (CoreGraphics/ImageIO, XCTest, Foundation).
- Keep `swiftlint --strict` clean. `IntegrationTests/` is lint-excluded.
- Every interaction re-resolves its `XCUIElement` on each attempt and shares one
  time budget (`Waiter`) — preserve this in any new interaction/wait.

## Review checklist (correctness first)

1. **No false-green asserts.** `assertVisible` must mean *on screen* (hittable),
   not merely "exists with a frame". Use `assertPresent` for the soft case.
2. **Flaky-safety intact.** Re-resolve on each attempt; one shared time budget.
3. **Synchronizer everywhere.** `config.synchronizer.waitForIdle` must run in
   *all* waits (interactions, collection asserts, `waitForAny`/`waitForAll`),
   not just `perform` — else an EarlGrey backend silently won't apply.
4. **Docstring examples compile** — match real signatures (e.g.
   `accessibilityIdentifierPolicy`, not a removed parameter).
5. **SwiftUI quirks**: label vs value (empty `value` → fall back to `label`);
   secure/formatted fields break delete-by-length clearing.
6. **CI is the trust anchor.** UI tests must actually run on a simulator green.

## Workflow

Branch → PR → **green CI (SwiftLint + unit + UI)** → merge. `main` is
protected; you cannot merge on red. Never `git push` to `main` directly.
Record notable changes in `CHANGELOG.md` under `[Unreleased]`.
