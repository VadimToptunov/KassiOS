import XCTest

/// Logs each action's start and outcome through a ``KassLogger``. Place it
/// *before* ``KassRetryInterceptor`` in the chain to log once per action;
/// *after* it to log every attempt.
public struct KassLoggingInterceptor: KassInterceptor {
    let logger: KassLogger

    public init(logger: KassLogger = ConsoleKassLogger()) {
        self.logger = logger
    }

    @MainActor
    public func intercept(_ context: KassActionContext, proceed: () throws -> Void) throws {
        logger.log("▶︎ \(context.name) — \(context.elementDescription)")
        do {
            try proceed()
            logger.log("✓ \(context.name)")
        } catch {
            logger.log("✗ \(context.name): \(error)")
            throw error
        }
    }
}

/// What to do with an iOS system permission dialog.
public enum KassSystemAlertAction: Sendable {
    /// Tap the affirmative button (Allow / OK / …).
    case accept
    /// Tap the negative button (Don't Allow / Cancel / …).
    case dismiss
}

/// Auto-handles iOS **system** dialogs (location, notifications, tracking/ATT,
/// photos, camera, Sign in with Apple, …) — a top source of XCUITest flake.
///
/// Unlike `addUIInterruptionMonitor`, which only fires on the *next* interaction
/// and needs a poke, this runs inside the action chain: it dismisses/accepts any
/// springboard alert before each wrapped action, and again afterwards in case
/// the action itself triggered one. Place it **after** ``KassRetryInterceptor``
/// so it runs on every attempt.
///
/// ```swift
/// config.interceptors = [KassRetryInterceptor(), KassSystemAlertInterceptor(.accept)]
/// ```
public struct KassSystemAlertInterceptor: KassInterceptor {
    let action: KassSystemAlertAction
    let acceptButtons: [String]
    let dismissButtons: [String]
    let logger: KassLogger

    /// - Parameters:
    ///   - action: whether to accept or dismiss dialogs (default `.accept`).
    ///   - accept / dismiss: button titles to try, in order. The defaults cover
    ///     the common iOS permission prompts; override for localized runs.
    ///   - logger: where a "present but unhandled" diagnostic is written.
    public init(
        _ action: KassSystemAlertAction = .accept,
        accept: [String] = [
            "Allow", "Allow While Using App", "Allow Once", "Always Allow",
            "OK", "Continue"
        ],
        dismiss: [String] = [
            "Don't Allow", "Ask App Not to Track", "Not Now", "Cancel"
        ],
        logger: KassLogger = ConsoleKassLogger()
    ) {
        self.action = action
        self.acceptButtons = accept
        self.dismissButtons = dismiss
        self.logger = logger
    }

    @MainActor
    public func intercept(_ context: KassActionContext, proceed: () throws -> Void) throws {
        handlePendingAlert()
        // Handle an alert the action itself raised, even if it then threw, so the
        // next retry attempt starts from a clean state.
        defer { handlePendingAlert() }
        try proceed()
    }

    /// The first candidate title that is present — the pure selection rule,
    /// factored out so it can be unit-tested without a running simulator.
    static func firstMatchingTitle(in candidates: [String], exists: (String) -> Bool) -> String? {
        candidates.first(where: exists)
    }

    /// Taps the first matching button on the frontmost springboard alert, if any.
    @MainActor
    private func handlePendingAlert() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        guard alert.exists else { return }
        let titles = action == .accept ? acceptButtons : dismissButtons
        if let match = Self.firstMatchingTitle(in: titles, exists: { alert.buttons[$0].exists }) {
            alert.buttons[match].tap()
        } else {
            // A dialog is up but none of our titles matched (localized, or a new
            // iOS wording). Say so loudly — otherwise the next action just fails
            // with a baffling "not hittable" against the modal-blocked screen.
            let found = alert.buttons.allElementsBoundByIndex.map(\.label)
            logger.log("⚠️ KassSystemAlertInterceptor: system alert present but none of \(titles) matched its buttons \(found)")
        }
    }
}
