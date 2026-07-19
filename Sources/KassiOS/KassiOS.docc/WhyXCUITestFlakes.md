# Why your XCUITest suite flakes

The four things that make raw XCUITest suites flaky — and what KassiOS does about
each.

## Overview

A flaky UI test is one that passes and fails on the same code. In XCUITest the
causes are predictable. Naming them makes the fixes obvious.

## 1. Timing you manage by hand

`waitForExistence(timeout:)` scattered before every tap is a manual state machine
you have to keep correct. Miss one and the test races the UI; set them all high
and a real failure takes the full timeout to surface.

KassiOS wraps every interaction in ``Waiter`` — it re-tries until the element is
ready or a single time budget elapses. You write the tap; the wait is implicit.

```swift
login.submit.tap()   // waits for existence + hittability, then taps
```

## 2. Stale element references

`let button = app.buttons["x"]` captures a snapshot. When the hierarchy reloads
(a navigation push, a list diff), that reference can go stale and the next action
throws.

``KassElement`` never caches. It stores a `() -> XCUIElement` closure and
**re-resolves on every attempt**, so a reload mid-retry just re-finds the element.

## 3. Retries that compound

Naive retry helpers give each nested wait its own timeout, so a three-level check
can blow out to 3× the budget — the suite gets slower *and* flakier.

KassiOS shares **one** budget across an interaction's retries (``Waiter``). A
custom multi-step condition uses the same guarantee via `flakySafely`:

```swift
flakySafely { try someCompoundCondition() }   // one budget, not one-per-step
```

## 4. Matching the wrong element by label

Matching by visible text passes until the copy changes or a localization shifts —
then it silently matches something else, or nothing.

Turn on strict identifiers (``KassIdentifierPolicy/enforce``) and KassiOS fails
loudly when an element was matched by label instead of a real
`accessibilityIdentifier` — pushing you toward stable selectors.

```swift
config = KassConfig(accessibilityIdentifierPolicy: .enforce)
```

## Going further: idle synchronization

Polling handles most flakiness. For the rest — animations and in-flight work that
finish *just* after a poll — plug a real idle backend via ``KassSynchronizer``
(there's an EarlGrey adapter reference in `Examples/`). Its `waitForIdle` runs
before interactions *and* inside collection assertions and the wait-combinators,
so the guarantee applies everywhere, not just taps.
