import Foundation
import SwiftUI

class DishDetailViewModel: ObservableObject {
    @Published var detail: DishDetail?
    @Published var isLoading: Bool = false
    @Published var isStreaming: Bool = false
    @Published var streamingTitle: String?
    @Published var streamingDescription: String = ""
    @Published var streamingMedia: [DishMedia] = []
    @Published var isDeepSearchingImages: Bool = false
    @Published var errorMessage: String?
    /// Per-dish advisory based on the user's saved preferences.
    @Published var advice: DishAdvice?

    private let service: DishService
    private let adviceService: DishAdviceService
    private let authService: AuthService
    private let initialLanguage: String?
    private let dishName: String
    private let originalDishName: String
    private let categoryOriginal: String?
    private let menuTitleOriginal: String?
    private var loadTask: Task<Void, Never>?
    private var imageTask: Task<Void, Never>?
    private var imageSearchGeneration = UUID()
    private var adviceTask: Task<Void, Never>?

    init(
        dishName: String,
        originalDishName: String,
        categoryOriginal: String? = nil,
        menuTitleOriginal: String? = nil,
        language: String? = nil,
        authService: AuthService
    ) {
        self.dishName = dishName
        self.originalDishName = originalDishName
        self.categoryOriginal = categoryOriginal
        self.menuTitleOriginal = menuTitleOriginal
        self.authService = authService
        self.initialLanguage = language
        self.service = DishService(authService: authService)
        self.adviceService = DishAdviceService(authService: authService)
        load()
    }

    deinit {
        loadTask?.cancel()
        imageTask?.cancel()
        adviceTask?.cancel()
    }
    
    func load() {
        loadTask?.cancel()
        imageTask?.cancel()
        adviceTask?.cancel()
        isLoading = true
        isStreaming = true
        detail = nil
        streamingTitle = nil
        streamingDescription = ""
        streamingMedia = []
        isDeepSearchingImages = false
        errorMessage = nil
        advice = nil
        let imageGeneration = UUID()
        imageSearchGeneration = imageGeneration

        let authToken = authService.getAuthToken()
        let userID = authService.currentUserID

        // Check the dish against the user's saved preferences in parallel with
        // the detail/image fetches so the advisory shows as soon as it's ready.
        adviceTask = Task { [weak self] in
            guard let self, let authToken, let userID else { return }
            guard let profile = try? await SupabaseClient().fetchProfile(authToken: authToken, userID: userID) else { return }

            let allergies = profile.allergies ?? []
            let diets = profile.dietaryPreferences ?? []
            let note = profile.preferenceNote ?? ""
            guard !allergies.isEmpty || !diets.isEmpty || !note.isEmpty else { return }

            do {
                let result = try await self.adviceService.advice(
                    dish: self.dishName,
                    description: "",
                    allergies: allergies,
                    diets: diets,
                    preferenceNote: note,
                    target: UserLanguagePreferences.appLanguage
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    withAnimation(PlatyMotion.softSpring) { self.advice = result }
                }
            } catch {
                print("Dish advice error: \(error)")
            }
        }

        let imageService = service
        let imageOriginalName = originalDishName
        let imageCategory = categoryOriginal
        let imageMenuContext = menuTitleOriginal
        imageTask = Task { [weak self] in
            do {
                let probe = try await imageService.getDishImages(
                    originalName: imageOriginalName,
                    categoryOriginal: imageCategory,
                    menuTitleOriginal: imageMenuContext
                )
                try Task.checkCancellation()

                let finalOutcome: DishImageSearchOutcome
                if probe.needsDeepSearch {
                    // A review-triggered response must include Gemini's
                    // qualifier. Never publish the probe images if a malformed
                    // response omits it.
                    guard let deepSearchTerm = probe.deepSearchTerm else {
                        return
                    }
                    let canContinue = await MainActor.run { [weak self] in
                        guard let self,
                              self.imageSearchGeneration == imageGeneration
                        else { return false }
                        withAnimation(PlatyMotion.ease) {
                            self.isDeepSearchingImages = true
                        }
                        return true
                    }
                    guard canContinue else { return }

                    finalOutcome = try await imageService.getDishImages(
                        originalName: imageOriginalName,
                        categoryOriginal: imageCategory,
                        menuTitleOriginal: imageMenuContext,
                        deepSearchTerm: deepSearchTerm
                    )
                    try Task.checkCancellation()
                } else {
                    finalOutcome = probe
                }

                await MainActor.run {
                    guard let self,
                          self.imageSearchGeneration == imageGeneration
                    else { return }
                    self.isDeepSearchingImages = false
                    guard !finalOutcome.media.isEmpty else { return }
                    self.streamingMedia = finalOutcome.media
                    if let detail = self.detail, detail.media.isEmpty {
                        self.detail = detail.replacingMedia(finalOutcome.media)
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self,
                          self.imageSearchGeneration == imageGeneration
                    else { return }
                    self.isDeepSearchingImages = false
                }
                print("Dish image error: \(error)")
            }
        }

        loadTask = Task { [weak self] in
            guard let self else { return }

            let language: String
            if let initialLanguage = self.initialLanguage {
                language = initialLanguage
            } else {
                language = await UserLanguagePreferences.resolveMenuLanguage(
                    authToken: authToken,
                    userID: userID
                )
            }

            do {
                let finalDetail = try await self.service.streamDishDetail(
                    dishName: self.dishName,
                    originalDishName: self.originalDishName,
                    categoryOriginal: self.categoryOriginal,
                    menuTitleOriginal: self.menuTitleOriginal,
                    language: language,
                    onTitle: { [weak self] title in
                        guard let viewModel = self else { return }
                        await MainActor.run {
                            viewModel.streamingTitle = title
                        }
                    },
                    onDelta: { [weak self] delta in
                        guard let viewModel = self else { return }
                        await MainActor.run {
                            withAnimation(.linear(duration: 0.06)) {
                                viewModel.streamingDescription += delta
                            }
                        }
                    },
                    onSnapshot: { [weak self] description in
                        guard let viewModel = self else { return }
                        await MainActor.run {
                            withAnimation(PlatyMotion.ease) {
                                viewModel.streamingDescription = description
                            }
                        }
                    }
                )

                await MainActor.run {
                    let mergedDetail = finalDetail.media.isEmpty && !self.streamingMedia.isEmpty
                        ? finalDetail.replacingMedia(self.streamingMedia)
                        : finalDetail
                    self.detail = mergedDetail
                    self.streamingTitle = finalDetail.name
                    self.streamingDescription = finalDetail.description
                    self.isLoading = false
                    self.isStreaming = false
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.isLoading = false
                    self.isStreaming = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.isStreaming = false
                    self.errorMessage = error.localizedDescription
                    print("Dish detail error: \(error)")
                }
            }
        }
    }

    func cancelImageSearch() {
        imageTask?.cancel()
        imageTask = nil
        imageSearchGeneration = UUID()
        isDeepSearchingImages = false
    }
}
