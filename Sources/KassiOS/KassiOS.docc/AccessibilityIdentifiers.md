# Accessibility identifiers

The naming convention KassiOS matches on — and how the enforcement, audit, and
lint keep you honest about it.

## Overview

Every KassiOS locator resolves by **accessibility identifier** — the string you
set with `.accessibilityIdentifier("…")` in the app and pass to a builder
(`button("login.submit")`) in a screen object. A consistent identifier scheme is
what makes a suite readable, collision-free, and mechanically checkable, so
KassiOS standardizes one.

## The convention: dot.camelCase, hierarchical

- **A single element:** `<screen>.<element>` — `login.email`, `login.submit`,
  `home.welcome`, `transfer.recipientField`.
- **Rows / repeated elements:** `<screen>.<collection>.<key>.<field>` —
  `markets.asset.AAPL.price`, `cart.item.SKU123.quantity`. The key
  (`AAPL`, `SKU123`) is the stable per-row identity.
- **Segments are `camelCase`; the dot separates levels.** No `snake_case`, no
  spaces.

Why hierarchical dots over flat `snake_case`:

- **Namespaced by screen**, so `login.submit` and `checkout.submit` never
  collide.
- **Reads as a path** — you can tell where an element lives from its id alone.
- **Scales to lists.** A per-row id like `markets.asset.\(symbol).price` is a
  natural, auditable parameterization (see below); a flat `markets_price` can't
  distinguish rows.

```swift
final class LoginScreen: KassScreen {
    lazy var email  = textField("login.email")
    lazy var submit = button("login.submit")
    override var onLoad: [KassElement] { [email, submit] }
}

final class MarketsScreen: KassScreen {
    // Per-row locator — the interpolated key is the stable row identity.
    func price(_ symbol: String) -> KassElement { staticText("markets.asset.\(symbol).price") }
}
```

## How the three guardrails read the convention

- **Runtime enforcement** (``KassConfig/accessibilityIdentifierPolicy``): with
  `.enforce`, an element matched *without* a real identifier fails the test,
  pointing at the exact `.accessibilityIdentifier("…")` to add. `.warn` only
  surfaces an Xcode message.
- **Runtime audit** (`auditAccessibilityIdentifiers()`): scans the current
  screen for hittable, interactive elements that carry *no* identifier at all.
- **Static lint** (`kassios-lint`, KAS002): flags an element built from an id
  that isn't a string literal — a bare variable or a call — because those can't
  be audited without running the test. **Interpolated string literals pass**
  (`"markets.asset.\(symbol).price"` still reveals the id's structure).

## For test authors and agents

Set the identifier in the app the moment you add a view; name it
`<screen>.<element>`. In tests, build locators from that same string. Keep
per-row ids parameterized by a stable key, not an array index — indices shift
when the list reorders.
