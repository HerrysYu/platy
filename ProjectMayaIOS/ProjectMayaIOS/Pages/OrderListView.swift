import SwiftUI

struct OrderListView: View {
    @EnvironmentObject private var orderManager: OrderManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PlatyScreenHeader(
                    title: "Order List",
                    subtitle: orderManager.items.isEmpty ? "Add dishes by tapping translated menu labels." : "\(orderManager.totalCount) dishes ready to review."
                )
                .platyEntrance()

                if orderManager.items.isEmpty {
                    emptyState
                        .platyEntrance(delay: 0.08)
                } else {
                    VStack(spacing: 12) {
                        ForEach(Array(orderManager.items.enumerated()), id: \.element.id) { index, item in
                            OrderCard(item: item)
                                .platyEntrance(delay: 0.04 * Double(index + 1))
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .animation(PlatyMotion.softSpring, value: orderManager.items)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 70)
            .padding(.bottom, 40)
        }
        .background(PlatyTheme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "cart")
                .font(.system(size: 54, weight: .semibold))
                .foregroundColor(PlatyTheme.textSecondary)

            Text("No dishes yet")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(PlatyTheme.textPrimary)

            Text("Tap a translated dish on the menu, then save it here.")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(PlatyTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 104)
        .padding(.horizontal, 28)
        .background(PlatyTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(PlatyTheme.border, lineWidth: 1)
        )
    }
}

private struct OrderCard: View {
    @EnvironmentObject private var orderManager: OrderManager
    let item: OrderItem

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(PlatyTheme.accent.opacity(0.16))
                Image(systemName: "fork.knife")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(PlatyTheme.accent)
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 5) {
                Text(item.dish.name)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(PlatyTheme.textPrimary)
                    .lineLimit(2)

                Text(item.originalName)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(PlatyTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            HStack(spacing: 10) {
                quantityButton("minus") { orderManager.decrement(item: item) }
                    .disabled(item.quantity <= 1)

                Text("\(item.quantity)")
                    .font(.system(size: 18, weight: .semibold).monospacedDigit())
                    .foregroundColor(PlatyTheme.textPrimary)
                    .frame(minWidth: 22)
                    .contentTransition(.numericText())
                    .animation(PlatyMotion.spring, value: item.quantity)

                quantityButton("plus") { orderManager.increment(item: item) }
            }

            Button(role: .destructive) {
                withAnimation(PlatyMotion.spring) {
                    orderManager.remove(item: item)
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(PlatyTheme.danger)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(PlatyPressStyle())
        }
        .padding(14)
        .background(PlatyTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(PlatyTheme.border, lineWidth: 1)
        )
    }

    private func quantityButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            withAnimation(PlatyMotion.spring) {
                action()
            }
        }) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .heavy))
                .foregroundColor(.black)
                .frame(width: 30, height: 30)
                .background(PlatyTheme.accent)
                .clipShape(Circle())
        }
        .buttonStyle(PlatyPressStyle(scale: 0.88))
    }
}

#Preview {
    NavigationStack {
        OrderListView()
            .environmentObject(OrderManager())
    }
}
