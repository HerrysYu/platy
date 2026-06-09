import SwiftUI

struct RotatedTextBox: View {
    var text: String
    var angle: Angle
    var height: CGFloat
    var width: CGFloat
    var scale: CGFloat = 1.0
    let borderColor: Color = PlatyTheme.accent.opacity(0.42)
    let foregroundColor: Color = .white
    let minimumScaleFactor: CGFloat = 0.62
    let cornerRadius: CGFloat = 10
    var onSelect: (String) -> Void = { _ in }
    @State private var didTap = false
    
    private var fontSize: CGFloat {
        Self.fontSize(for: height)
    }

    private var labelWidth: CGFloat {
        Self.preferredSize(for: text, boxWidth: width, boxHeight: height, scale: scale).width
    }

    private var labelHeight: CGFloat {
        Self.preferredSize(for: text, boxWidth: width, boxHeight: height, scale: scale).height
    }

    static func preferredSize(for text: String, boxWidth: CGFloat, boxHeight: CGFloat, scale: CGFloat = 1) -> CGSize {
        let fontSize = fontSize(for: boxHeight)
        let estimatedWidth = CGFloat(text.count) * fontSize * 0.52 + 22
        let boxAnchoredWidth = max(46, boxWidth + 18)
        let maxWidth = scale > 1.35 ? CGFloat(250) : CGFloat(196)
        let width = min(maxWidth, max(boxAnchoredWidth, min(estimatedWidth, boxAnchoredWidth * 2.2)))
        let needsSecondLine = estimatedWidth > width * 1.08
        let height = needsSecondLine
            ? max(38, min(54, boxHeight + 26))
            : max(24, min(36, boxHeight + 12))
        return CGSize(width: width, height: height)
    }

    private static func fontSize(for boxHeight: CGFloat) -> CGFloat {
        min(14, max(9, boxHeight * 0.46))
    }

    var body: some View {
        ZStack {
            Color.clear
            Button(action: {
                withAnimation(PlatyMotion.fast) {
                    didTap = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                    withAnimation(PlatyMotion.fast) {
                        didTap = false
                    }
                }
                onSelect(text)
            }) {
                Text(text)
                    .font(.system(size: fontSize, weight: .heavy, design: .rounded))
                    .foregroundColor(foregroundColor)
                    .lineLimit(labelHeight > 37 ? 2 : 1)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.72)
                    .padding(.horizontal, 8)
                    .padding(.vertical, labelHeight > 37 ? 4 : 0)
                    .frame(width: labelWidth, height: labelHeight)
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(Color.black.opacity(0.46))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(didTap ? PlatyTheme.accent : borderColor.opacity(0.7), lineWidth: didTap ? 2 : 1)
                    )
                    .shadow(color: didTap ? PlatyTheme.accent.opacity(0.22) : .black.opacity(0.18), radius: didTap ? 10 : 4, y: 2)
            }
            .buttonStyle(PlatyPressStyle(scale: 0.94))
            .scaleEffect(didTap ? 1.06 : 1)
        }
        .rotationEffect(angle)
    }
}
