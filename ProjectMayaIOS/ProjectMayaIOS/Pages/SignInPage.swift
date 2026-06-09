import SwiftUI

struct SignInPage: View {
    @ObservedObject var authService: AuthService
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var rememberCredentials: Bool = false
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""
    @State private var showClearCredentialsAlert: Bool = false
    @State private var showTokenInfo: Bool = false
    @State private var navigateToSignUp: Bool = false
    @State private var navigateToVerification: Bool = false
    @State private var unverifiedEmail: String = ""
    
    init(authService: AuthService) {
        self.authService = authService
    }

    var body: some View {
        ZStack {
            PlatyTheme.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 30) {
                Spacer(minLength: 92)

                PlatyScreenHeader(
                    title: "Welcome Back",
                    subtitle: "Sign in to continue your food journey"
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
                        textContentType: .password
                    )
                }
                .platyEntrance(delay: 0.08)

                HStack {
                    Button {
                        rememberCredentials.toggle()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: rememberCredentials ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(rememberCredentials ? PlatyTheme.accent : PlatyTheme.textSecondary)
                            Text("Remember me")
                                .foregroundStyle(PlatyTheme.textSecondary)
                        }
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    if rememberCredentials {
                        Button("Clear saved") {
                            presentClearCredentialsAlert()
                        }
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(PlatyTheme.textTertiary)
                    }
                }
                .platyEntrance(delay: 0.14)

                PlatyPrimaryButton(
                    title: authService.isLoading ? "Signing In..." : "Sign In",
                    systemImage: "arrow.right",
                    isLoading: authService.isLoading,
                    isDisabled: email.isEmpty || password.isEmpty,
                    action: signIn
                )
                .platyEntrance(delay: 0.2)

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    Spacer()
                    Text("Don't have an account?")
                        .foregroundColor(PlatyTheme.textSecondary)
                    Button("Create one") {
                        navigateToSignUp = true
                    }
                    .fontWeight(.bold)
                    .foregroundColor(PlatyTheme.accent)
                    Spacer()
                }
                .padding(.bottom, 40)
                .platyEntrance(delay: 0.26)
            }
            .padding(.horizontal, 24)
        }
        .navigationBarBackButtonHidden(true)
        .navigationDestination(isPresented: $navigateToSignUp) {
            SignUpPage(authService: authService)
        }
        .navigationDestination(isPresented: $navigateToVerification) {
            EmailVerificationPage(email: unverifiedEmail, authService: authService)
        }
        .alert("Message", isPresented: $showAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
        .alert("Clear Saved Credentials", isPresented: $showClearCredentialsAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                clearSavedCredentials()
                rememberCredentials = false
                email = ""
                password = ""
            }
        } message: {
            Text("This will remove your saved email and password from this device.")
        }
        .onAppear {
            loadSavedCredentials()
        }
    }

    private func signIn() {
        guard !email.isEmpty else {
            showAlert(message: "Please enter your email")
            return
        }

        guard !password.isEmpty else {
            showAlert(message: "Please enter your password")
            return
        }

        authService.signIn(email: email, password: password) { result in
            switch result {
            case .success(_):
                print("Sign in successful - authService.isAuthenticated will trigger app-level navigation")
                
                // Save credentials if user opted to remember them
                if rememberCredentials {
                    saveCredentials()
                } else {
                    clearSavedCredentials()
                }
                
                // The app-level view will automatically show LandingPage when authService.isAuthenticated becomes true
            case .failure(let error):
                print("Sign in failed: \(error.localizedDescription)")
                
                // Check if it's an unverified user
                if let authError = error as? AuthError,
                   case .userNotConfirmed(let userEmail) = authError {
                    DispatchQueue.main.async {
                        self.unverifiedEmail = userEmail
                        self.navigateToVerification = true
                    }
                } else {
                    showAlert(message: "Sign in failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func signOut() {
        authService.signOut()
        email = ""
        password = ""
        showAlert(message: "Signed out successfully")
    }

    private func showAlert(message: String) {
        alertMessage = message
        showAlert = true
    }
    
    private func presentClearCredentialsAlert() {
        showClearCredentialsAlert = true
    }
    
    // MARK: - Credential Management
    
    private func loadSavedCredentials() {
        // Load remember preference
        rememberCredentials = UserDefaults.standard.getRememberCredentials()
        
        // Load email if remember is enabled
        if rememberCredentials {
            if let savedEmail = UserDefaults.standard.getSavedEmail() {
                email = savedEmail
                
                // Load password from Keychain
                if let savedPassword = KeychainManager.shared.getPassword(for: savedEmail) {
                    password = savedPassword
                }
            }
        }
    }
    
    private func saveCredentials() {
        UserDefaults.standard.setRememberCredentials(true)
        UserDefaults.standard.setSavedEmail(email)
        
        let success = KeychainManager.shared.savePassword(password, for: email)
        if success {
            print("✅ Credentials saved successfully")
        } else {
            print("❌ Failed to save credentials to Keychain")
        }
    }
    
    private func clearSavedCredentials() {
        UserDefaults.standard.setRememberCredentials(false)
        
        if let savedEmail = UserDefaults.standard.getSavedEmail() {
            let _ = KeychainManager.shared.deletePassword(for: savedEmail)
        }
        
        UserDefaults.standard.removeSavedEmail()
        print("🗑️ Saved credentials cleared")
    }
}

#Preview {
    SignInPage(authService: AuthService())
}
