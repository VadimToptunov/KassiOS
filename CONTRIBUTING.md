# Contributing to KassiOS

Thanks for helping! KassiOS is a small, zero-dependency DSL over XCUITest — the
bar is **correctness** (it's a test framework) and **no false-green tests**.

## Setup

The library wraps XCUITest, so it builds with Xcode, not bare `swift build`.
Command Line Tools are often active, so point at the full Xcode:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

- **Unit tests** (fast, pure logic):
  `xcodebuild test -scheme KassiOS -destination 'platform=macOS'`
- **Integration UI tests** (real demo app on the simulator):
  `cd IntegrationTests && ruby gen.rb && xcodebuild test -scheme KassDemoUITests -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`
- **Lint:** `swiftlint lint --strict`

## Ground rules

- **Zero dependencies** in the core. Prefer system frameworks.
- Keep the core invariant: every interaction re-resolves its `XCUIElement` on
  each attempt and shares one time budget (`Waiter`). Route new waits through
  `config.synchronizer.waitForIdle`.
- `assertVisible` means **on screen** (hittable) — never "just exists". Soft
  checks go in `assertPresent`.
- Public API carries `///` docs, and docstring examples must compile.
- `swiftlint --strict` stays clean; new logic gets a test.

## Workflow

1. Fork and branch (`feature/…` or `fix/…`).
2. Make the change; add/adjust tests; update `CHANGELOG.md` under `[Unreleased]`.
3. Open a PR. CI runs **SwiftLint + unit tests + UI tests on a simulator** — all
   three must be green (`main` is protected; nothing merges red).
4. A maintainer reviews. Design/API decisions are made by humans, not bots.

## Reporting bugs & requesting features

Use the issue templates. For a UI-test bug, include the failing screen's
accessibility tree (KassiOS attaches `app.debugDescription` on failure) and the
device/OS — snapshot and visibility behaviour are device-specific.
