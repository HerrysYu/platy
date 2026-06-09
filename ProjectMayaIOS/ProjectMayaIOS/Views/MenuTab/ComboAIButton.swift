import SwiftUI

/// Floating "AI combo" orb shown on the menu page.
/// A slowly rotating gradient rim + breathing glow keeps it alive without
/// being distracting; tapping it fires a quick burst before the action.
struct ComboAIButton: View {
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = false
    @State private var breathe = false
    @State private var burst = false
    @State private var ringExpand = false

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
        Button {
            guard !burst else { return }
            burst = true
            ringExpand = false
            withAnimation(.easeOut(duration: 0.42)) {
                ringExpand = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                burst = false
                action()
            }
        } label: {
            ZStack {
                // Breathing glow halo
                Circle()
                    .fill(PlatyTheme.accent.opacity(breathe ? 0.34 : 0.16))
                    .frame(width: 64, height: 64)
                    .blur(radius: breathe ? 14 : 9)

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

                Image(systemName: "sparkles")
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [PlatyTheme.accentStrong, PlatyTheme.accent],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .scaleEffect(breathe ? 1.06 : 0.96)
                    .shadow(color: PlatyTheme.accent.opacity(0.6), radius: breathe ? 7 : 3)

                // Tap burst ring
                Circle()
                    .stroke(PlatyTheme.accentStrong, lineWidth: 2)
                    .frame(width: 56, height: 56)
                    .scaleEffect(ringExpand ? 1.55 : 1)
                    .opacity(ringExpand ? 0 : (burst ? 0.8 : 0))
            }
            .frame(width: 64, height: 64)
            .scaleEffect(burst ? 1.12 : 1)
            .animation(PlatyMotion.fast, value: burst)
        }
        .buttonStyle(PlatyPressStyle(scale: 0.9))
        .accessibilityLabel("AI combo recommendation")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 9).repeatForever(autoreverses: false)) {
                spin = true
            }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                breathe = true
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
