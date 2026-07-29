import SwiftUI
import WebKit
import CoreLocation

/// Requests location permission — used to raise a real iOS system dialog so the
/// `KassSystemAlertInterceptor` can be exercised end-to-end.
@MainActor
final class LocationRequester: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var status = "notDetermined"
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
    }

    func request() { manager.requestWhenInUseAuthorization() }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let authorization = manager.authorizationStatus
        Task { @MainActor in
            switch authorization {
            case .authorizedWhenInUse, .authorizedAlways: self.status = "authorized"
            case .denied, .restricted: self.status = "denied"
            default: self.status = "notDetermined"
            }
        }
    }
}

/// A tiny SwiftUI app with proper accessibility identifiers, used as the host
/// for KassiOS's own UI tests. Every interactive element carries an id, so
/// strict mode (`.enforce`) passes against it.
@main
struct KassDemoApp: App {
    init() {
        // Honour KassiOS's `config.disableAnimations` (a UI test can't disable
        // another process's animations, so the app opts in on startup).
        if ProcessInfo.processInfo.environment["KASS_DISABLE_ANIMATIONS"] == "1" {
            UIView.setAnimationsEnabled(false)
        }
        // In-app network stub bridge (real apps guard this with `#if DEBUG`).
        KassiOSStubs.installIfConfigured()
    }

    var body: some Scene {
        WindowGroup { RootView() }
    }
}

struct RootView: View {
    @State private var loggedIn = false
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            if loggedIn {
                HomeView()
            } else {
                LoginView(email: $email, password: $password) { loggedIn = true }
            }
        }
    }
}

struct LoginView: View {
    @Binding var email: String
    @Binding var password: String
    var onSignIn: () -> Void
    @State private var showError = false

    var body: some View {
        VStack(spacing: 16) {
            TextField("Email", text: $email)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .accessibilityIdentifier("email")

            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("password")

            if showError {
                Text("Please enter an email")
                    .foregroundColor(.red)
                    .accessibilityIdentifier("loginError")
            }

            Button("Sign In") {
                if email.isEmpty { showError = true } else { onSignIn() }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("signIn")

            // Deliberately WITHOUT an accessibility identifier — the
            // accessibility audit should flag it.
            Button("Help") {}

            Spacer()
        }
        .padding()
        .navigationTitle("Login")
    }
}

struct HomeView: View {
    @State private var notificationsOn = false
    @State private var showAlert = false
    @State private var refreshed = false
    @State private var fetchResult = ""
    @StateObject private var location = LocationRequester()
    private let items = (0..<12).map { "Item \($0)" }

    // KassiOS 0.24.0 "deep assertions" coverage.
    @State private var toastVisible = false
    @State private var duplicateRowsEnabled = false

    // KassiOS 1.1.0 "API ergonomics" coverage.
    @State private var ergonomicsToggleOn = false

    private var dedupRows: [String] {
        duplicateRowsEnabled ? ["Row A", "Row A", "Row C"] : ["Row A", "Row B", "Row C"]
    }

    private func showToast() {
        toastVisible = true
        // Long enough to survive XCUITest's own post-tap idle-settle overhead
        // (which can itself take ~1s) and still be a "transient", not a
        // persistent element `assertVisible` would catch just as well.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { toastVisible = false }
    }

    private func fetch() {
        let url = URL(string: "https://api.example.com/user")!
        URLSession.shared.dataTask(with: url) { data, _, error in
            DispatchQueue.main.async {
                if let error = error as? URLError {
                    fetchResult = error.code == .notConnectedToInternet ? "offline" : "error"
                } else {
                    fetchResult = String(data: data ?? Data(), encoding: .utf8) ?? ""
                }
            }
        }.resume()
    }

    var body: some View {
        Form {
            Button("Fetch") { fetch() }
                .accessibilityIdentifier("fetchButton")
            Text(fetchResult)
                .accessibilityIdentifier("fetchResult")

            if refreshed {
                Text("Refreshed")
                    .accessibilityIdentifier("refreshed")
            }

            Text("Welcome!")
                .font(.headline)
                .accessibilityIdentifier("welcome")

            Text(Locale.current.identifier)
                .accessibilityIdentifier("locale")

            Button("Request Location") { location.request() }
                .accessibilityIdentifier("requestLocation")
            Text(location.status)
                .accessibilityIdentifier("locationStatus")

            Toggle("Notifications", isOn: $notificationsOn)
                .accessibilityIdentifier("notifications")

            Button("Show Alert") { showAlert = true }
                .accessibilityIdentifier("showAlert")
                .alert("Heads up", isPresented: $showAlert) {
                    Button("OK", role: .cancel) { }
                }

            NavigationLink("Open Web") { WebScreenView() }
                .accessibilityIdentifier("openWeb")

            Section("Items") {
                ForEach(items.indices, id: \.self) { index in
                    Text(items[index]).accessibilityIdentifier("item-\(index)")
                }
            }

            // KassiOS 0.23.0 locator-ergonomics coverage. Placed last (after
            // "Items") so it doesn't shift earlier rows out of the initially
            // rendered window — SwiftUI's Form/List renders lazily, so these
            // rows themselves need a scroll to become reachable; see the tests.
            Section("Locator ergonomics") {
                // A label-only decoy ("decoyMatch" is its *label*, not an id) placed
                // before the real id'd element — proves id-first resolution picks
                // the real id over the earlier, coincidental label match.
                Text("decoyMatch")
                Text("Real Target").accessibilityIdentifier("decoyMatch")

                // Same accessibility identifier on two rows with different labels —
                // simulates SwiftUI's container-id propagation (e.g. a sheet's id
                // landing on every child) that `element(id:label:)` disambiguates.
                Text("Alpha").accessibilityIdentifier("duplicateId")
                Text("Beta").accessibilityIdentifier("duplicateId")
            }

            // KassiOS 0.24.0 "deep assertions" coverage. Placed last so it
            // doesn't shift earlier lazily-rendered rows out of the initially
            // rendered window.
            Section("Deep assertions") {
                // A formatted amount — an exact string match is the wrong tool
                // here (rounding/locale), `assertValue(closeTo:)` is the point.
                Text("$92.50")
                    .accessibilityIdentifier("deep.amount")

                // A small row list that can be made to duplicate a label, for
                // `assertNoDuplicates` (simulates a pagination bug).
                ForEach(dedupRows.indices, id: \.self) { index in
                    Text(dedupRows[index]).accessibilityIdentifier("deep.row-\(index)")
                }
                Button(duplicateRowsEnabled ? "Fix Duplicate Row" : "Duplicate a Row") {
                    duplicateRowsEnabled.toggle()
                }
                .accessibilityIdentifier("deep.duplicateToggle")

                // A transient toast — visible for ~2s — for `assertAppears`.
                Button("Show Toast") { showToast() }
                    .accessibilityIdentifier("deep.toast.button")
            }

            // KassiOS 1.1.0 "API ergonomics" coverage. Placed last so it
            // doesn't shift earlier lazily-rendered rows out of the initially
            // rendered window.
            Section("API ergonomics") {
                Toggle("Ergonomics Toggle", isOn: $ergonomicsToggleOn)
                    .accessibilityIdentifier("ergonomics.toggle")
                Button("Ergonomics Button") {}
                    .accessibilityIdentifier("ergonomics.button")
            }
        }
        .refreshable { refreshed = true }
        .accessibilityIdentifier("itemsList")
        .navigationTitle("Home")
        // The toast is an overlay, not a Form row: a List/Form re-layout on
        // insert/remove is slow enough that a brief pulse can get delayed or
        // coalesced away before it ever renders — an overlay updates immediately.
        .overlay(alignment: .bottom) {
            if toastVisible {
                Text("Success!")
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityIdentifier("deep.toast")
                    .padding(.bottom, 24)
            }
        }
    }
}

struct WebScreenView: View {
    var body: some View {
        DemoWebView()
            .navigationTitle("Web")
    }
}

struct DemoWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.loadHTMLString(
            "<html><head><meta name='viewport' content='initial-scale=1'></head>"
            + "<body><h1>Hello Web</h1><p>Web content</p></body></html>",
            baseURL: nil
        )
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
