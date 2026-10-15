# Hardware stubbing

Some flows depend on hardware the simulator cannot provide: a camera-based
scanner (QR / barcode), Bluetooth (CoreBluetooth), or NFC (CoreNFC). XCUITest is
a UI driver, not a signal injector, and the simulator has no camera, radio, or
NFC — so these cannot be driven the way network traffic can (there is no
`URLProtocol`-style hook for hardware).

The only robust path is a seam **inside the app**: abstract each device behind
your own protocol, use the real implementation in production, and in debug feed
that protocol from a fixture the test supplies. KassiOS makes that handshake
uniform; it cannot remove the seam.

> Location and push notifications are **not** here — they go through the simctl
> device API (`KassDevice`), which can drive them without an in-app seam.

## The handshake

1. **Test side** — build a `KassHardwareFixture` and launch with it:

   ```swift
   func test_scanCheckoutCode() {
       launch(hardware: .init(scanner: [.code("4006381333931", symbology: "ean13")]))
       onScreen(ScannerScreen.self) { $0.scanButton.tap() }
       onScreen(CartScreen.self) { $0.total.assertVisible() }
   }
   ```

   The fixture is encoded into the `KASS_HARDWARE_JSON` launch environment
   variable (the same mechanism as `launch(networkStubs:)`).

2. **App side** — your production code depends on your own protocol:

   ```swift
   protocol ScannerProviding { func scan() async throws -> String }
   ```

   In the composition root, inject the real scanner in production and, in debug,
   a tiny adapter over `KassScannerStub` when a fixture is present:

   ```swift
   #if DEBUG
   import KassiOSStubs

   func makeScanner() -> ScannerProviding {
       guard let fixture = KassiOSStubs.hardwareFixture() else { return RealScanner() }
       let stub = KassScannerStub(fixture.scanner)
       return StubScanner(stub)   // 3-line adapter: `scan()` returns `try stub.next()`
   }
   #else
   func makeScanner() -> ScannerProviding { RealScanner() }
   #endif
   ```

`KassiOSStubs` ships the replay helpers — `KassScannerStub`, `KassBLEStub`,
`KassNFCStub` — so the adapter is only the mapping from your protocol to theirs.

## What the stubs replay

- **Scanner** — a queue of results consumed in order; a result can script a
  thrown error to exercise the scan-failure branch.
- **Bluetooth** — the peripherals a scan "discovers" and their scheduled
  characteristic notifications (hex payload + delay).
- **NFC** — a queue of NDEF tags, likewise able to script a read failure.

## Scope: static vs dynamic

This is **Tier 1 — static**: the fixture is primed at launch and replayed on
demand. It covers the large majority of flows ("when the user scans, return
X"). It needs no extra infrastructure beyond the launch environment.

**Tier 2 — dynamic** (delivering an event mid-test, e.g. "the peripheral
disconnects now") would need a debug-only in-app control channel and is
intentionally **not** built yet. Add it only when a real test needs an event
to arrive after launch.
