//
//  ColorExtendsion.swift
//  ProjectMayaIOS
//
//  Created by Herrys Yu on 2025-06-30.
//

import SwiftUI
import UIKit

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red:   Double((hex & 0xFF0000) >> 16) / 255,
            green: Double((hex & 0x00FF00) >> 8)  / 255,
            blue:  Double(hex & 0x0000FF)        / 255,
            opacity: alpha
        )
    }
}

enum PlatyTheme {
    static let background = Color.black
    static let surface = Color(hex: 0x171717)
    static let surfaceRaised = Color(hex: 0x202020)
    static let surfaceMuted = Color(hex: 0x101010)
    static let border = Color.white.opacity(0.12)
    static let divider = Color.white.opacity(0.08)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.56)
    static let textTertiary = Color.white.opacity(0.36)
    static let accent = Color(hex: 0xF5C47E)
    static let accentStrong = Color(hex: 0xFFDD31)
    static let danger = Color(hex: 0xFF6B6B)
}

enum PlatyMotion {
    static let spring = Animation.spring(response: 0.34, dampingFraction: 0.78)
    static let softSpring = Animation.spring(response: 0.48, dampingFraction: 0.86)
    static let smooth = Animation.spring(response: 0.48, dampingFraction: 0.86)
    static let ease = Animation.easeInOut(duration: 0.22)
    static let fast = Animation.spring(response: 0.2, dampingFraction: 0.72)
    static let scan = Animation.easeInOut(duration: 1.55)
}

struct PlatyPressStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(PlatyMotion.spring, value: configuration.isPressed)
    }
}

struct PlatyEntrance: ViewModifier {
    let delay: Double
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 16)
            .onAppear {
                withAnimation(PlatyMotion.softSpring.delay(delay)) {
                    isVisible = true
                }
            }
    }
}

extension View {
    func platyEntrance(delay: Double = 0) -> some View {
        modifier(PlatyEntrance(delay: delay))
    }

    func platyFloat(distance: CGFloat = 4, duration: Double = 2.4, delay: Double = 0) -> some View {
        modifier(PlatyFloat(distance: distance, duration: duration, delay: delay))
    }

    func platyShimmer(active: Bool = true, duration: Double = 1.8) -> some View {
        modifier(PlatyShimmer(active: active, duration: duration))
    }
}

struct PlatyFloat: ViewModifier {
    let distance: CGFloat
    let duration: Double
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isFloating = false

    func body(content: Content) -> some View {
        content
            .offset(y: reduceMotion ? 0 : (isFloating ? -distance : distance))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: duration).delay(delay).repeatForever(autoreverses: true)) {
                    isFloating = true
                }
            }
    }
}

struct PlatyShimmer: ViewModifier {
    let active: Bool
    let duration: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if active && !reduceMotion {
                    GeometryReader { geometry in
                        LinearGradient(
                            colors: [
                                .clear,
                                Color.white.opacity(0.18),
                                Color.white.opacity(0.28),
                                .clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: max(58, geometry.size.width * 0.42), height: geometry.size.height * 1.45)
                        .rotationEffect(.degrees(18))
                        .offset(
                            x: sweep ? geometry.size.width * 1.15 : -geometry.size.width * 0.72,
                            y: -geometry.size.height * 0.18
                        )
                        .blendMode(.screen)
                    }
                    .allowsHitTesting(false)
                }
            }
            .clipped()
            .onAppear {
                startSweepIfNeeded()
            }
            .onChange(of: active) { _, isActive in
                if isActive {
                    startSweepIfNeeded()
                } else {
                    sweep = false
                }
            }
    }

    private func startSweepIfNeeded() {
        guard active && !reduceMotion else { return }
        sweep = false
        DispatchQueue.main.async {
            withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                sweep = true
            }
        }
    }
}

struct PlatyScreenHeader: View {
    let title: String
    let subtitle: String?
    var alignment: HorizontalAlignment = .leading
    var frameAlignment: Alignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 10) {
            Text(title)
                .font(.system(size: 42, weight: .heavy, design: .rounded))
                .foregroundStyle(PlatyTheme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.74)

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(PlatyTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment)
    }
}

struct PlatyPrimaryButton: View {
    let title: String
    var systemImage: String?
    var isLoading = false
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.black)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .bold))
                }

                Text(title)
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 66)
            .background((isDisabled || isLoading) ? PlatyTheme.accent.opacity(0.52) : PlatyTheme.accent)
            .clipShape(Capsule())
        }
        .buttonStyle(PlatyPressStyle())
        .disabled(isDisabled || isLoading)
    }
}

struct PlatyIconButton: View {
    let systemName: String
    var size: CGFloat = 50
    var foreground: Color = PlatyTheme.textPrimary
    var background: Color = PlatyTheme.surfaceRaised
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
                .background(background)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(PlatyTheme.border, lineWidth: 1)
                )
        }
        .buttonStyle(PlatyPressStyle(scale: 0.9))
    }
}

struct PlatyInputField: View {
    let placeholder: String
    let systemImage: String
    @Binding var text: String
    var isSecure = false
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType?

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(PlatyTheme.textSecondary)
                .frame(width: 24)

            Group {
                if isSecure {
                    SecureField("", text: $text, prompt: Text(placeholder).foregroundColor(PlatyTheme.textTertiary))
                        .textContentType(textContentType)
                } else {
                    TextField("", text: $text, prompt: Text(placeholder).foregroundColor(PlatyTheme.textTertiary))
                        .keyboardType(keyboardType)
                        .textContentType(textContentType)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .foregroundStyle(PlatyTheme.textPrimary)
        }
        .padding(.horizontal, 18)
        .frame(height: 64)
        .background(PlatyTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(PlatyTheme.border, lineWidth: 1)
        )
    }
}

struct PlatyCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(PlatyTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(PlatyTheme.border, lineWidth: 1)
            )
    }
}

struct PlatySectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 23, weight: .heavy, design: .rounded))
            .foregroundStyle(PlatyTheme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PlatyScanPreview: View {
    var height: CGFloat = 124
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep = false

    private let rowWidths: [CGFloat] = [0.68, 0.9, 0.52, 0.8, 0.45]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(PlatyTheme.surfaceRaised)

                VStack(alignment: .leading, spacing: 11) {
                    ForEach(Array(rowWidths.enumerated()), id: \.offset) { index, width in
                        Capsule()
                            .fill(index == 1 ? PlatyTheme.accent.opacity(0.7) : Color.white.opacity(0.16))
                            .frame(width: max(34, geometry.size.width * width), height: index == 1 ? 9 : 7)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)

                if !reduceMotion {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    PlatyTheme.accent.opacity(0),
                                    PlatyTheme.accent.opacity(0.95),
                                    PlatyTheme.accent.opacity(0)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 3)
                        .shadow(color: PlatyTheme.accent.opacity(0.85), radius: 10)
                        .padding(.horizontal, 14)
                        .offset(y: sweep ? (geometry.size.height / 2 - 17) : (-geometry.size.height / 2 + 17))
                }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(PlatyTheme.border, lineWidth: 1)
        )
        .onAppear {
            guard !reduceMotion else { return }
            sweep = false
            withAnimation(PlatyMotion.scan.delay(0.2).repeatForever(autoreverses: true)) {
                sweep = true
            }
        }
    }
}
