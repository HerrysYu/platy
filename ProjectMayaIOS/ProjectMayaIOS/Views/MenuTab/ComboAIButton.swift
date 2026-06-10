import SwiftUI

/// Floating combo-recommendation button shown on the menu page.
/// A slowly rotating gradient rim keeps it alive; press feedback comes from
/// the shared PlatyPressStyle scale instead of extra glow layers.
struct ComboAIButton: View {
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = false

    private var rimGradient: AngularGradient {
        AngularGradient(
            gradient: Gradient(colors: [
                PlatyTheme.accent,
                PlatyTheme.accentStrong,
                Color(hex: 0xFF9F6B),
                PlatyTheme.accent
            ]),
            center: .center
        )
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                // Rotating gradient rim
                Circle()
                    .stroke(rimGradient, lineWidth: 2.4)
                    .frame(width: 62, height: 62)
                    .rotationEffect(.degrees(spin ? 360 : 0))

                // Body
                Circle()
                    .fill(Color.black.opacity(0.82))
                    .frame(width: 56, height: 56)
                    .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))

                Image(systemName: "fork.knife")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(PlatyTheme.accent)
            }
            .frame(width: 64, height: 64)
        }
        .buttonStyle(PlatyPressStyle(scale: 0.9))
        .accessibilityLabel("AI combo recommendation")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 9).repeatForever(autoreverses: false)) {
                spin = true
            }
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        ComboAIButton {}
    }
}
