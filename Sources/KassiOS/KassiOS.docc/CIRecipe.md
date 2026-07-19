# Running KassiOS on CI

A working recipe for parallelization, retries, and machine-readable reports.

## Overview

KassiOS tests are ordinary XCUITest cases, so any CI that runs `xcodebuild test`
runs them. The pieces worth getting right are parallelization, an automatic retry
for the residual flake, and reports your CI can read.

## xcodebuild

```bash
set -o pipefail
xcodebuild test \
  -scheme MyAppUITests \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest' \
  -parallel-testing-enabled YES \
  -retry-tests-on-failure -test-iterations 3 \
  -resultBundlePath Results.xcresult
```

- `-parallel-testing-enabled YES` clones the simulator and shards test classes
  across the clones.
- `-retry-tests-on-failure -test-iterations 3` retries only the failures, up to
  three attempts — a safety net for genuine flake, not a substitute for the
  built-in waits.
- `-resultBundlePath` keeps the `.xcresult`, which already carries the failure
  screenshot and accessibility tree KassiOS attaches on a red test.

## Reports CI can read

Wire a ``KassReporter`` once in a ``KassSuite`` and every test in it emits the
report:

```swift
class CIBase: KassSuite {
    override func configure() -> KassConfig {
        KassConfig(reporter: JUnitReporter(), accessibilityIdentifierPolicy: .enforce)
    }
}
```

``JUnitReporter`` writes one JUnit XML file per test to `$KASS_JUNIT_PATH` (most
CIs ingest JUnit natively). For richer, step-nested reports use ``AllureReporter``
instead. Set the path in the test target's environment:

```bash
xcodebuild test … KASS_JUNIT_PATH=$PWD/junit
```

## Snapshots on CI

Snapshot references are pixel-exact, so pin the simulator device and OS, and point
`$KASS_SNAPSHOTS_PATH` at a committed folder (the source-adjacent default may be
read-only on a build agent):

```bash
xcodebuild test … KASS_SNAPSHOTS_PATH=$PWD/__Snapshots__
```

Never record on CI — a missing reference *fails* the test by design so you commit
it deliberately.

## Fastlane

If you use Fastlane, `scan` maps onto the same flags:

```ruby
scan(
  scheme: "MyAppUITests",
  devices: ["iPhone 15"],
  parallel_testing: true,
  number_of_retries: 3,
  result_bundle: true,
  xcargs: "KASS_JUNIT_PATH=#{Dir.pwd}/junit"
)
```

## A note on determinism

Parallelization multiplies any hidden shared state (a logged-in session, a seeded
database) into race conditions. Keep each test self-launching (`launch()` /
`relaunch()`), drive setup through launch arguments and `launch(stubs:)`, and
avoid depending on order — the same discipline that makes the suite fast makes it
reproducible.
