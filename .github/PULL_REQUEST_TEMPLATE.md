<!-- Thanks for contributing to KassiOS! -->

## What & why

<!-- What does this change and what problem does it solve? -->

## Checklist

- [ ] `swiftlint --strict` is clean
- [ ] Unit tests pass (`xcodebuild test -scheme KassiOS -destination 'platform=macOS'`)
- [ ] Integration UI tests pass (if behaviour could affect real UI)
- [ ] New logic has a test; public API has `///` docs (examples compile)
- [ ] No new external dependency (KassiOS core is zero-dependency)
- [ ] `CHANGELOG.md` updated under `[Unreleased]`
- [ ] `assertVisible` still means *on screen* (no false-green); new waits go
      through `config.synchronizer.waitForIdle`
