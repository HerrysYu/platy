//
//  FoodCard.swift
//  ProjectMayaIOS
//
//  Created by ChatGPT on 2025-07-23.
//

import Foundation
import SwiftUI
struct DishDetailView: View {
    @StateObject private var viewModel: DishDetailViewModel
    @EnvironmentObject private var orderManager: OrderManager
    @Environment(\.dismiss) private var dismiss
    @State private var didAdd = false
    @State private var aboutDescriptionHeight: CGFloat = 0
    
    private let originalName: String
    init(translatedName: String, originalName: String, authService: AuthService) {
        self.originalName = originalName
        _viewModel = StateObject(wrappedValue: DishDetailViewModel(dishName: translatedName, authService: authService))
    }
    
    var body: some View {
        ZStack {
            PlatyTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let dish = displayedDish {
                        dishContent(
                            dish,
                            isStreaming: viewModel.detail == nil && viewModel.isStreaming,
                            canAddToOrder: viewModel.detail != nil
                        )
                            .platyEntrance()
                    } else if let errorMessage = viewModel.errorMessage {
                        errorState(errorMessage)
                    } else {
                        loadingState
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 26)
                .padding(.bottom, 38)
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var displayedDish: DishDetail? {
        if let detail = viewModel.detail {
            if detail.media.isEmpty && !viewModel.streamingMedia.isEmpty {
                return detail.replacingMedia(viewModel.streamingMedia)
            }
            return detail
        }

        if viewModel.isStreaming || !viewModel.streamingDescription.isEmpty {
            return DishDetail(
                name: viewModel.streamingTitle ?? originalName,
                description: viewModel.streamingDescription,
                ingredients: nil,
                tags: [],
                media: viewModel.streamingMedia
            )
        }

        return nil
    }
    
    private func dishContent(_ dish: DishDetail, isStreaming: Bool, canAddToOrder: Bool) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text(originalName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(PlatyTheme.accent)
                    .lineLimit(1)

                Text(dish.name)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(PlatyTheme.textPrimary)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)

                Text("Verify details with the restaurant before ordering.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(PlatyTheme.textSecondary)

                if isStreaming {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(PlatyTheme.accent)
                            .scaleEffect(0.72)
                        Text("Writing details")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(PlatyTheme.accent)
                    }
                    .padding(.top, 2)
                }
            }

            if let advice = viewModel.advice, advice.hasConcerns {
                DishAdviceCard(advice: advice)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if !dish.media.isEmpty {
                mediaStrip(dish.media)
            }

            PlatyCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("About")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(PlatyTheme.textPrimary)

                    if dish.description.isEmpty && isStreaming {
                        PlatyScanPreview(height: 96)
                            .platyShimmer()
                    } else {
                        AboutDescriptionText(
                            text: dish.description,
                            isStreaming: isStreaming
                        )
                        .readAboutDescriptionHeight()
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(
                minHeight: aboutCardMinimumHeight(
                    isShowingPlaceholder: dish.description.isEmpty && isStreaming
                ),
                alignment: .topLeading
            )
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .onPreferenceChange(AboutDescriptionHeightPreferenceKey.self) { height in
                withAnimation(PlatyMotion.ease) {
                    aboutDescriptionHeight = height
                }
            }

            if let ingredients = dish.ingredients, !ingredients.isEmpty {
                PlatyCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Usually includes")
                            .font(.system(size: 21, weight: .bold))
                            .foregroundStyle(PlatyTheme.textPrimary)

                        Text(ingredients.joined(separator: ", "))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(PlatyTheme.textSecondary)
                    }
                    .padding(18)
                }
            }

            if let tags = dish.tags, !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(tags, id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(PlatyTheme.textPrimary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(PlatyTheme.surface)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(PlatyTheme.border, lineWidth: 1))
                        }
                    }
                }
            }

            // Ordering only needs the dish name, which we have immediately, so
            // the button is usable without waiting for the description.
            PlatyPrimaryButton(
                title: didAdd ? "Added" : "Add to Order",
                systemImage: didAdd ? "checkmark" : "plus",
                isDisabled: didAdd
            ) {
                withAnimation(PlatyMotion.spring) {
                    orderManager.add(dish: dish, originalName: originalName)
                    didAdd = true
                }
            }
        }
    }

    private func aboutCardMinimumHeight(isShowingPlaceholder: Bool) -> CGFloat {
        if isShowingPlaceholder {
            return 21 + 12 + 96 + 36
        }

        return max(132, 21 + 12 + aboutDescriptionHeight + 36)
    }

    private var loadingState: some View {
        VStack(spacing: 18) {
            ProgressView()
                .tint(PlatyTheme.accent)
                .scaleEffect(1.2)
            Text("Finding dish details")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(PlatyTheme.textPrimary)
            Text("Images and descriptions may take a moment.")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(PlatyTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 100)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(PlatyTheme.danger)

            Text("Could not load dish details")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(PlatyTheme.textPrimary)

            Text(message)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(PlatyTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            PlatyPrimaryButton(title: "Try Again", systemImage: "arrow.clockwise") {
                viewModel.load()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 76)
    }

    private func mediaStrip(_ media: [DishMedia]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(media, id: \.imageURL) { item in
                    if let url = makeSecureURL(from: item.imageURL) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                ProgressView()
                                    .tint(PlatyTheme.accent)
                                    .frame(width: 156, height: 156)
                                    .background(PlatyTheme.surface)
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 156, height: 156)
                                    .clipped()
                            case .failure:
                                Image(systemName: "photo")
                                    .font(.system(size: 32))
                                    .foregroundStyle(PlatyTheme.textSecondary)
                                    .frame(width: 156, height: 156)
                                    .background(PlatyTheme.surface)
                            @unknown default:
                                EmptyView()
                                    .frame(width: 156, height: 156)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(PlatyTheme.border, lineWidth: 1)
                        )
                    }
                }
            }
        }
    }
    
    private func makeSecureURL(from string: String) -> URL? {
        var urlString = string
        if urlString.hasPrefix("http://") {
            urlString = urlString.replacingOccurrences(of: "http://", with: "https://")
        }
        
        guard let encoded = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }        
        return URL(string: encoded)
    }
}

private struct DishAdviceCard: View {
    let advice: DishAdvice

    private var tint: Color {
        switch advice.verdict {
        case .avoid: return PlatyTheme.danger
        case .caution, .ok: return PlatyTheme.accent
        }
    }

    private var icon: String {
        switch advice.verdict {
        case .avoid: return "exclamationmark.octagon.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .ok: return "checkmark.seal.fill"
        }
    }

    private var heading: LocalizedStringKey {
        switch advice.verdict {
        case .avoid: return "Best to avoid"
        case .caution: return "Worth checking"
        case .ok: return "Fits your preferences"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(tint)
                Text(heading)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(PlatyTheme.textPrimary)
                Spacer()
                Text("For you")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(tint)
                    .textCase(.uppercase)
                    .kerning(0.8)
            }

            if !advice.summary.isEmpty {
                Text(advice.summary)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(PlatyTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !advice.notes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(advice.notes, id: \.self) { note in
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 5))
                                .foregroundStyle(tint)
                                .padding(.top, 7)
                            Text(note)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(PlatyTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(tint.opacity(0.45), lineWidth: 1)
        )
    }
}

private struct AboutDescriptionText: View {
    let text: String
    let isStreaming: Bool

    var body: some View {
        Text(text + (isStreaming ? " |" : ""))
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(PlatyTheme.textSecondary)
            .lineLimit(nil)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .layoutPriority(10)
            .animation(.linear(duration: 0.06), value: text)
    }
}

private struct AboutDescriptionHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private extension View {
    func readAboutDescriptionHeight() -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: AboutDescriptionHeightPreferenceKey.self,
                    value: geometry.size.height
                )
            }
        }
    }
}
