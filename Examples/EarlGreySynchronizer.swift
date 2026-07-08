// Illustrative only — an optional synchronization backend.
//
// KassiOS core stays dependency-free, so this adapter lives in Examples rather
// than a compiled target. To use it, add EarlGrey to your UI test target,
// uncomment the import and body, then drop it into your config:
//
//     config = KassConfig(synchronizer: EarlGreySynchronizer())
//
// EarlGrey's thread executor drains the app's main run loop until it is idle —
// animations finished, network settled, no pending main-queue work — which is a
// stronger guarantee than polling for element existence alone.

// import EarlGrey
import Foundation
import KassiOS

/// Blocks each interaction attempt until EarlGrey reports the app is idle.
struct EarlGreySynchronizer: KassSynchronizer {
    func waitForIdle(timeout: TimeInterval) {
        // With EarlGrey linked, forward to its thread executor, e.g.:
        //
        //     GREYUIThreadExecutor.sharedInstance()
        //         .drainUntilIdle(withTimeout: timeout)
        //
        // (API name varies by EarlGrey version; see the EarlGrey docs.)
    }
}
