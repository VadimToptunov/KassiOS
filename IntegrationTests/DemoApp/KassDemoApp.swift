import SwiftUI

/// A tiny SwiftUI app with proper accessibility identifiers, used as the host
/// for KassiOS's own UI tests. Every interactive element carries an id, so
/// strict mode (`.enforce`) passes against it.
@main
struct KassDemoApp: App {
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
    private let items = (0..<12).map { "Item \($0)" }

    var body: some View {
        Form {
            Text("Welcome!")
                .font(.headline)
                .accessibilityIdentifier("welcome")

            Toggle("Notifications", isOn: $notificationsOn)
                .accessibilityIdentifier("notifications")

            Button("Show Alert") { showAlert = true }
                .accessibilityIdentifier("showAlert")
                .alert("Heads up", isPresented: $showAlert) {
                    Button("OK", role: .cancel) { }
                }

            Section("Items") {
                ForEach(items.indices, id: \.self) { index in
                    Text(items[index]).accessibilityIdentifier("item-\(index)")
                }
            }
        }
        .accessibilityIdentifier("itemsList")
        .navigationTitle("Home")
    }
}
