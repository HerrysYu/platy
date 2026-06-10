import SwiftUI

struct SignUpPage: View {
    @ObservedObject var authService: AuthService
    @EnvironmentObject private var mealHistoryService: MealHistoryService
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""
    @State private var navigateToLanding: Bool = false
    @State private var navigateToVerification: Bool = false
    @Environment(\.dismiss) private var dismiss

    init(authService: AuthService) {
        self.authService = authService
    }

    var body: some View {
        ZStack {
            PlatyTheme.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 28) {
                Spacer(minLength: 68)

                PlatyScreenHeader(
                    title: "Create Account",
                    subtitle: "Save your menus and meals across devices"
                )
                .platyEntrance()

                VStack(spacing: 14) {
                    PlatyInputField(
                        placeholder: "Email",
                        systemImage: "envelope",
                        text: $email,
                        keyboardType: .emailAddress,
                        textContentType: .username
                    )

                    PlatyInputField(
                        placeholder: "Password",
                        systemImage: "lock",
                        text: $password,
                        isSecure: true,
                        textContentType: .newPassword
                    )

                    PlatyInputField(
                        placeholder: "Confirm password",
                        systemImage: "checkmark.shield",
                        text: $confirmPassword,
                        isSecure: true,
                        textContentType: .newPassword
                    )
                }
                .platyEntrance(delay: 0.06)

                PlatyPrimaryButton(
                    title: authService.isLoading ? "Creating Account..." : "Sign Up",
                    systemImage: "person.badge.plus",
                    isLoading: authService.isLoading,
                    isDisabled: email.isEmpty || password.isEmpty || confirmPassword.isEmpty,
                    action: signUp
                )
                .platyEntrance(delay: 0.12)

                Spacer()

                HStack(spacing: 8) {
                    Spacer()
                    Text("Already have an account?")
                        .foregroundColor(PlatyTheme.textSecondary)
                    Button("Sign In") {
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .foregroundColor(PlatyTheme.accent)
                    Spacer()
                }
                .padding(.bottom, 40)
                .platyEntrance(delay: 0.2)
            }
            .padding(.horizontal, 24)
        }
        .navigationDestination(isPresented: $navigateToLanding) {
            LandingPage(authService: authService)
        }
        .navigationDestination(isPresented: $navigateToVerification) {
            EmailVerificationPage(email: email, authService: authService)
        }
        .onChange(of: navigateToLanding) { _, newValue in
            print("navigateToLanding changed to: \(newValue)")
        }
        .alert("Message", isPresented: $showAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
    }

    private func signUp() {
        guard !email.isEmpty else {
            showAlert(message: String(localized: "Please enter your email"))
            return
        }

        guard !password.isEmpty else {
            showAlert(message: String(localized: "Please enter your password"))
            return
        }

        guard !confirmPassword.isEmpty else {
            showAlert(message: String(localized: "Please confirm your password"))
            return
        }

        guard password == confirmPassword else {
            showAlert(message: String(localized: "Passwords do not match"))
            return
        }

        guard password.count >= 8 else {
            showAlert(message: String(localized: "Password must be at least 8 characters long"))
            return
        }

        authService.signUp(email: email, password: password) { result in
            switch result {
            case .success(let message):
                print("Sign up successful: \(message)")
                DispatchQueue.main.async {
                    if authService.isAuthenticated {
                        self.navigateToLanding = true
                    } else {
                        self.navigateToVerification = true
                    }
                }
            case .failure(let error):
                print("Sign up failed: \(error.localizedDescription)")
                showAlert(message: String(localized: "Sign up failed: \(error.localizedDescription)"))
            }
        }
    }

    private func showAlert(message: String) {
        alertMessage = message
        showAlert = true
    }
}

#Preview {
    SignUpPage(authService: AuthService())
}
