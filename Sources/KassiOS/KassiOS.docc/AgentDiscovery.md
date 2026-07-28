# Agent discovery

Two agent-facing features that make a wrong-id guess self-correct and feed a
coding agent's scaffold, instead of leaving it to eyeball `debugDescription`.

## Overview

An AI author writing a KassiOS screen object is guessing at accessibility
identifiers without ever having seen the running app. Two features close that
loop: a failure that names the closest real id, and an inventory to build
screen objects from in the first place.

## "Did you mean?"

When a locator built from an accessibility identifier fails because the
element genuinely doesn't exist, the failure message appends the closest
actual identifiers/labels found on the current screen:

```
KassiOS: text 'welcom' — assertVisible failed: does not exist
  ↳ element not found in the current hierarchy
  ↳ did you mean: 'welcome', 'Welcome!'?
```

Candidates come from one bounded walk of the screen (400 elements); ranking is
case-insensitive Levenshtein distance via
``KassIdentifierSuggestions/nearest(to:among:max:maxDistance:)`` — its own
pure, unit-tested function — capped so an unrelated element never gets
suggested. Gate it off with `KassConfig(suggestSimilarIdentifiersOnFailure:
false)`; it defaults to `true` because the walk only runs once an assertion
has already failed.

## The identifier inventory

``KassDevice/dumpIdentifiers(includingUnidentified:)`` returns every element's
`{ identifier, type, label, isHittable }` as a `Codable`
``KassIdentifierInfo`` — the same bounded walk, reused. Hand it (or
``KassDevice/attachIdentifierInventory(includingUnidentified:)``'s JSON
artifact) to a coding agent to scaffold `KassScreen` properties, or use it to
discover what's actually on screen instead of guessing at ids up front.

```swift
let inventory = device.dumpIdentifiers()
device.attachIdentifierInventory()   // + pretty JSON attached to the report
```
