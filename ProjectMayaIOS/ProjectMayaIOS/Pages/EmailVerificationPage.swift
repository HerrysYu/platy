import SwiftUI

struct EmailVerificationPage: View {
    @ObservedObject var authService: AuthService
    @State private var verificationCode: String = ""
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""
    @State private var verificationSucceeded: Bool = false
    @State private var navigateToSignIn: Bool = false
    @Environment(\.dismiss) private var dismiss
    
    let email: String
    
    init(email: String, authService: AuthService) {
        self.email = email
        self.authService = authService
    }

    var body: some View {
        ZStack {
            PlatyTheme.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 28) {
                Spacer(minLength: 70)

                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "envelope.badge.shield.half.filled")
                        .font(.system(size: 58, weight: .bold))
                        .foregroundColor(PlatyTheme.accent)
                        .symbolEffect(.pulse, options: .repeating)

                    PlatyScreenHeader(
                        title: "Check Your Email",
                        subtitle: "We sent a 6-digit verification code to \(email)"
                    )
                }
                .platyEntrance()

                PlatyCard {
                    TextField("", text: $verificationCode, prompt: Text("Enter 6-digit code").foregroundColor(PlatyTheme.textTertiary))
                        .keyboardType(.numberPad)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.center)
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .tracking(5)
                        .foregroundStyle(PlatyTheme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 76)
                        .padding(.horizontal, 18)
                }
                .platyEntrance(delay: 0.08)

                PlatyPrimaryButton(
                    title: authService.isLoading ? "Verifying..." : "Verify Account",
                    systemImage: "checkmark.circle",
                    isLoading: authService.isLoading,
                    isDisabled: verificationCode.isEmpty,
                    action: verifyCode
                )
                .platyEntrance(delay: 0.14)

                Button(action: resendCode) {
                    HStack {
                        if authService.isLoading {
                            ProgressView()
                                .tint(PlatyTheme.accent)
                                .scaleEffect(0.6)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text(authService.isLoading ? "Sending..." : "Resend Code")
                    }
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(PlatyTheme.accent)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PlatyPressStyle())
                .disabled(authService.isLoading)
                .platyEntrance(delay: 0.2)

                Spacer()

                VStack(spacing: 8) {
                    Text("Didn't receive the code?")
                    Text("Check your spam folder or try resending.")
                }
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(PlatyTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 40)
            }
            .padding(.horizontal, 24)
        }
        .navigationDestination(isPresented: $navigateToSignIn) {
            SignInPage(authService: authService)
        }
        .navigationBarBackButtonHidden(false)
        .alert("Verification", isPresented: $showAlert) {
            if verificationSucceeded {
                Button("Sign In") {
                    navigateToSignIn = true
                }
            } else {
                Button("OK") {}
            }
        } message: {
            Text(alertMessage)
        }
    }

    private func verifyCode() {
        guard !verificationCode.isEmpty else {
            showAlert(message: String(localized: "Please enter the verification code"))
            return
        }

        guard verificationCode.count == 6 else {
            showAlert(message: String(localized: "Verification code must be 6 digits"))
            return
        }

        authService.confirmSignUp(email: email, code: verificationCode) { result in
            switch result {
            case .success(let message):
                print("Verification successful: \(message)")
                DispatchQueue.main.async {
                    self.verificationSucceeded = true
                    self.showAlert(message: String(localized: "Account verified successfully! You can now sign in."))
                }
            case .failure(let error):
                print("Verification failed: \(error.localizedDescription)")
                showAlert(message: String(localized: "Verification failed: \(error.localizedDescription)"))
            }
        }
    }

    private func resendCode() {
        authService.resendConfirmationCode(email: email) { result in
            switch result {
            case .success(let message):
                print("Resend successful: \(message)")
                DispatchQueue.main.async {
                    self.showAlert(message: String(localized: "Verification code sent! Check your email."))
                }
            case .failure(let error):
                print("Resend failed: \(error.localizedDescription)")
                showAlert(message: String(localized: "Failed to resend code: \(error.localizedDescription)"))
            }
        }
    }

    private func showAlert(message: String) {
        alertMessage = message
        showAlert = true
    }
}

#Preview {
    EmailVerificationPage(email: "example@email.com", authService: AuthService())
}
