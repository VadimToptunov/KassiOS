# Static linting with kassios-lint

Catch brittle screen objects at compile time — before you launch the simulator.

## Overview

``KassAuditSeverity`` and `auditAccessibilityIdentifiers()` run at *test time*,
on a live app: they can only flag a screen once it has rendered. `kassios-lint`
is the compile-time twin. It parses your screen-object *source* with SwiftSyntax
and reports the same class of problems statically, across **every** screen —
even ones no test has exercised yet.

Two rules ship today:

- **KAS001 — empty `onLoad`.** A ``KassScreen`` subclass that never declares a
  non-empty ``KassScreen/onLoad``. That's the "I have arrived" condition
  `onScreen` and `navigate(to:)` wait on; without it, navigation can't verify a
  screen actually loaded. This is the static twin of the empty-`onLoad` warning
  `navigate(to:)` logs at runtime — but it fires for screens you haven't run.
- **KAS002 — dynamic identifier.** An element builder (`button`, `staticText`,
  `element(_:type:)`, the scoped `descendant`, …) whose identifier argument
  isn't a static string literal (an interpolation like `"row_\(i)"`, or a
  variable). Such an identifier can't be audited or enforced without running the
  test, so the linter surfaces it up front.

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

## The MVP boundary

To keep false positives at zero, KAS001/KAS002 only recognize a class whose own
inheritance clause literally lists `KassScreen`; a subclass of a subclass in
another file isn't traced. Likewise a branchy `onLoad` (an `if/else` that
returns different arrays) is treated as clean rather than guessed at. The tool is
a fast, high-signal guardrail — not a type checker.
