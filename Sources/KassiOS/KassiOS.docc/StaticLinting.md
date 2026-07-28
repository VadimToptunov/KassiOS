# Static linting with kassios-lint

Catch brittle screen objects at compile time — before you launch the simulator.

## Overview

``KassAuditSeverity`` and `auditAccessibilityIdentifiers()` run at *test time*,
on a live app: they can only flag a screen once it has rendered. `kassios-lint`
is the compile-time twin. It parses your screen-object *source* with SwiftSyntax
and reports the same class of problems statically, across **every** screen —
even ones no test has exercised yet.

Three rules ship today:

- **KAS001 — empty `onLoad`.** A ``KassScreen`` subclass whose *resolved*
  `onLoad` — its own override, or (absent one) the nearest ancestor's, walking
  up the traced base-class chain — is empty or missing. That's the "I have
  arrived" condition `onScreen` and `navigate(to:)` wait on; without it,
  navigation can't verify a screen actually loaded. This is the static twin of
  the empty-`onLoad` warning `navigate(to:)` logs at runtime — but it fires for
  screens you haven't run.
- **KAS002 — dynamic identifier.** An element builder (`button`, `staticText`,
  `element(_:type:)`, the scoped `descendant`, …) whose identifier argument
  isn't a static string literal (an interpolation like `"row_\(i)"`, or a
  variable). Such an identifier can't be audited or enforced without running the
  test, so the linter surfaces it up front. A reviewed, deliberately dynamic
  case can suppress the finding with a trailing `// kassios:ignore-id` comment
  on the flagged call's own line — see "Suppressing a finding" below.
- **KAS003 — interactions outside a Robot.** A ``KassTestCase`` subclass's test
  method with 5 or more inline element interactions (`tap`, `typeText`,
  `swipeUp`, …) — a soft nudge to extract a reusable flow into a ``KassRobot``
  instead of inlining a long, hard-to-reuse script. It never fires inside a
  `KassRobot` subclass's own methods, since that's exactly where those
  interactions belong.

## Base classes are traced

A class counts as a `KassScreen` (or `KassTestCase`/`KassRobot`) subclass if it
inherits the root type directly, or inherits *any other class already known to
be one* — resolved as a fixpoint over every class declared in the files you
lint together, so any number of hierarchy levels resolves. That means

```swift
// CBScreen.swift
class CBScreen: KassScreen {
    override var onLoad: [KassElement] { [staticText("logo")] }
}

// HomeScreen.swift
final class HomeScreen: CBScreen {
    var balance: KassElement { staticText("balance") }
}
```

is recognized even though `HomeScreen` never mentions `KassScreen` directly,
*and* even though the two classes live in different files — as long as both
files are passed to the linter together (the CLI already does this; see
"Cross-file resolution" below).

## Suppressing a finding

A `// kassios:ignore-id` comment on the same line as a flagged KAS002 call
suppresses that one finding — for a reviewed, deliberately dynamic identifier
you don't want the linter re-flagging on every run:

```swift
func row(_ id: String) -> KassElement { cell(id) } // kassios:ignore-id
```

The check is trivia-based (a real comment, not raw text), so the same phrase
sitting inside a string-literal argument on that line does **not** suppress
anything — only an actual `//` or `///` comment counts. Because the match is
line-based, keep at most one flagged builder call per line, or they'll share
the same suppression.

## Why it's a separate package

KassiOS's core promise is **zero dependencies** — adding it to your UI-test
target pulls in nothing. SwiftSyntax is a large dependency, so the linter lives
in a **nested** package at `Plugins/`, invisible to anyone depending on the
`KassiOS` library: SPM resolves only the root manifest, which never references
swift-syntax. You opt into the tool explicitly.

## Running it

From a checkout of the KassiOS repo (or after vendoring the `Plugins/` folder):

```sh
cd Plugins
swift run kassios-lint ../MyApp/UITests
```

Each finding prints as `file:line:col: warning: message [RULE]`. By default the
tool exits `0` (findings are informational); pass `--strict` to exit non-zero on
any finding, which is what you want in CI:

```sh
swift run kassios-lint --strict ../MyApp/UITests
```

It's also registered as an SPM command plugin:

```sh
swift package kassios-lint
```

## Cross-file resolution

The CLI (`main.swift`) collects every `.swift` file under the paths you pass
and lints them together with the batch entry point,
`lint(sources:)`, so a base class declared in one file is resolved for
subclasses declared in any other. If you call the library directly, prefer
`lint(sources:)` over the single-file `lint(source:filePath:)` for the same
reason — the single-file entry point only sees same-file bases (it exists
mainly for isolated unit testing).

## The MVP boundary

To keep false positives at zero, a branchy `onLoad` (an `if/else` that returns
different arrays) is treated as clean rather than guessed at, and KAS003's
threshold is deliberately conservative (5+ interactions) so a simple,
`onScreen`-only test never trips it. The tool is a fast, high-signal
guardrail — not a type checker.
