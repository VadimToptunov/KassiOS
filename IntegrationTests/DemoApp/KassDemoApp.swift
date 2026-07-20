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
    @StateObject private var location = LocationRequester()
    private let items = (0..<12).map { "Item \($0)" }

    var body: some View {
        Form {
            if refreshed {
                Text("Refreshed")
                    .accessibilityIdentifier("refreshed")
            }

            Text("Welcome!")
                .font(.headline)
                .accessibilityIdentifier("welcome")

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
        }
        .refreshable { refreshed = true }
        .accessibilityIdentifier("itemsList")
        .navigationTitle("Home")
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
