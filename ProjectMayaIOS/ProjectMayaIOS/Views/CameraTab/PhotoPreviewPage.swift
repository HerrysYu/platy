import SwiftUI
import Vision

let translationModelGlobal: TranslationModel = TranslationModel()

struct DoneButton: View {
    let images: [UIImage]
    let authService: AuthService
    @EnvironmentObject private var orderManager: OrderManager
    @State private var showMenuPage = false
    @State private var menuImages: [MenuImage] = []
    @State private var menuBlocks: [MenuBlocks] = []
    @State private var isProcessing = false
    
    var body: some View {
        Button(action: {
            processImagesAndNavigate()
        }) {
            ZStack {
                // Invisible sizing ghost keeps the capsule width stable, so the
                // button doesn't jump when the state content swaps.
                stateContent(icon: "arrow.right", title: "Translate Menu")
                    .opacity(0)

                if isProcessing {
                    HStack(spacing: 9) {
                        ProcessingArc()
                        Text("Translating")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundColor(.black)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                } else {
                    stateContent(icon: "arrow.right", title: "Translate Menu")
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
        }
        .background(isProcessing ? PlatyTheme.accent.opacity(0.82) : PlatyTheme.accent)
        .clipShape(Capsule())
        .shadow(
            color: PlatyTheme.accent.opacity(isProcessing ? 0.42 : 0.28),
            radius: isProcessing ? 18 : 14,
            y: 6
        )
        .buttonStyle(PlatyPressStyle())
        .disabled(isProcessing)
        .animation(PlatyMotion.spring, value: isProcessing)
        .navigationDestination(isPresented: $showMenuPage) {
            MenuPage(menuImageList: menuImages, menuBlocksList: menuBlocks, authService: authService)
        }
    }

    private func stateContent(icon: String, title: LocalizedStringKey) -> some View {
        HStack(spacing: 9) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
            Image(systemName: icon)
                .font(.system(size: 15, weight: .heavy))
        }
        .foregroundColor(.black)
    }
    
    private func processImagesAndNavigate() {
        isProcessing = true
        let authToken = authService.getAuthToken()
        let userID = authService.currentUserID

        Task {
            let targetLanguage = await UserLanguagePreferences.resolveMenuLanguage(
                authToken: authToken,
                userID: userID
            )

            await MainActor.run {
                processImagesAndNavigate(targetLanguage: targetLanguage)
            }
        }
    }

    private func processImagesAndNavigate(targetLanguage: String) {
        print("🔄 Starting image processing and translation to \(targetLanguage)...")
        
        let group = DispatchGroup()
        let imageCount = images.count
        var processedMenuImages: [MenuImage] = Array(repeating: MenuImage(image: UIImage(), height: 0, width: 0), count: imageCount)
        var processedMenuBlocks: [MenuBlocks] = Array(repeating: MenuBlocks(BlockList: BlockList(blocks: [])), count: imageCount)
        
        for (index, image) in images.enumerated() {
            group.enter()
            processSingleImage(image, index: index, targetLanguage: targetLanguage) { menuImage, menuBlock in
                DispatchQueue.main.async {
                    print("📦 Storing results for image \(index + 1) at index \(index)")
                    // Use index to maintain proper order
                    processedMenuImages[index] = menuImage
                    processedMenuBlocks[index] = menuBlock
                    print("✅ Image \(index + 1) stored with \(menuBlock.blockList.blocks?.count ?? 0) blocks")
                    group.leave()
                }
            }
        }
        
        group.notify(queue: .main) {
            self.menuImages = processedMenuImages
            self.menuBlocks = processedMenuBlocks
            self.isProcessing = false
            
            // Start ongoing meal in OrderManager
            self.orderManager.startOngoingMeal(images: processedMenuImages, blocks: processedMenuBlocks)
            
            self.showMenuPage = true
            print("✅ Navigation to MenuPage ready! Processed \(processedMenuImages.count) images")
        }
    }
    
    private func processSingleImage(
        _ image: UIImage,
        index: Int,
        targetLanguage: String,
        completion: @escaping (MenuImage, MenuBlocks) -> Void
    ) {
        let menuImage = MenuImage(
            image: image,
            height: Double(image.size.height),
            width: Double(image.size.width)
        )
        
        print("🔄 Starting processing for image \(index + 1)")
        
        // Step 1: Perform local OCR
        LocalOCRService.performOCR(on: image) { ocrImageResult in
            guard let ocrImageResult = ocrImageResult else {
                print("❌ Local OCR failed for image \(index + 1)")
                completion(menuImage, MenuBlocks(BlockList: BlockList(blocks: [])))
                return
            }
            
            print("✅ Local OCR completed for image \(index + 1). Found \(ocrImageResult.ocrResults.count) text blocks")
            
            Task {
                let imageSize = CGSize(width: ocrImageResult.imageWidth, height: ocrImageResult.imageHeight)
                let filterResult = await SmartMenuTextFilter.current().filter(ocrImageResult.ocrResults, imageSize: imageSize)
                let filteredOCRResult = ocrImageResult.applying(results: filterResult.overlayResults)

                print("🧠 Smart filter kept \(filterResult.kept.count), uncertain \(filterResult.uncertain.count), dropped \(filterResult.dropped.count) for image \(index + 1)")

                await MainActor.run {
                    // Step 2: Send OCR results for translation - create fresh service instance
                    let translationService = TranslationService(authService: self.authService)
                    print("🌐 Starting translation for image \(index + 1) to \(targetLanguage)...")

                    translationService.processOCRResults(ocrImageResult: filteredOCRResult, targetLanguage: targetLanguage) { result in
                        switch result {
                        case .success(let response):
                            print("✅ Image \(index + 1) translation SUCCESS - received \(response.boxes.count) translated boxes")
                            let menuBlock = self.convertOCRProcessingToMenuBlocks(result)
                            print("🎯 Image \(index + 1) final blocks: \(menuBlock.blockList.blocks?.count ?? 0)")
                            completion(menuImage, menuBlock)
                        case .failure(let error):
                            print("❌ Image \(index + 1) translation FAILED: \(error.localizedDescription)")
                            let fallbackBlocks = self.convertOCRToMenuBlocks(filteredOCRResult)
                            completion(menuImage, fallbackBlocks)
                        }
                    }
                }
            }
        }
    }
    
    private func convertOCRProcessingToMenuBlocks(_ result: Result<OCRProcessingResponse, Error>) -> MenuBlocks {
        switch result {
        case .success(let ocrResponse):
            let textBlocks: [TextBlock] = ocrResponse.boxes.map { box in
                TextBlock(
                    text: box.originalText,
                    angle: Double(box.rotation),
                    box2D: [
                        CGFloat(box.y),           // ymin (box2D[0])
                        CGFloat(box.x),           // xmin (box2D[1])
                        CGFloat(box.y + box.height),   // ymax (box2D[2])
                        CGFloat(box.x + box.width)   // xmax (box2D[3])
                    ],
                    translatedText: box.translatedText
                )
            }
            return MenuBlocks(BlockList: BlockList(blocks: textBlocks))
            
        case .failure(let error):
            print("❌ OCR Processing failed: \(error.localizedDescription)")
            return MenuBlocks(BlockList: BlockList(blocks: []))
        }
    }
    
    private func convertOCRToMenuBlocks(_ imageResult: OCRImageResult?) -> MenuBlocks {
        guard let imageResult = imageResult else {
            return MenuBlocks(BlockList: BlockList(blocks: []))
        }
        let textBlocks: [TextBlock] = imageResult.ocrResults.map { res in
            TextBlock(
                text: res.text,
                angle: res.angle,
                box2D: res.boundingBox.box2D,
                translatedText: res.text
            )
        }
        return MenuBlocks(BlockList: BlockList(blocks: textBlocks))
    }
    
    // Keep the old converter for future use
    private func convertTranslationToMenuBlocks(_ result: Result<TranslationResponse, Error>) -> MenuBlocks {
        switch result {
        case .success(let translationResponse):
            var textBlocks: [TextBlock] = []
            
            for box in translationResponse.boxes {
                let textBlock = TextBlock(
                    text: box.originalText,
                    angle: Double(box.rotation),
                    box2D: [
                        CGFloat(box.y),           // ymin (box2D[0])
                        CGFloat(box.x),           // xmin (box2D[1])
                        CGFloat(box.y + box.height),   // ymax (box2D[2])
                        CGFloat(box.x + box.width)   // xmax (box2D[3])
                    ],
                    translatedText: box.translatedText
                )
                textBlocks.append(textBlock)
            }
            
            let blockList = BlockList(blocks: textBlocks)
            return MenuBlocks(BlockList: blockList)
            
        case .failure(let error):
            print("❌ Translation failed: \(error.localizedDescription)")
            return MenuBlocks(BlockList: BlockList(blocks: []))
        }
    }
}

/// Small spinning arc used inside the translate button while processing.
private struct ProcessingArc: View {
    @State private var spin = false

    var body: some View {
        Circle()
            .trim(from: 0.12, to: 0.88)
            .stroke(Color.black, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            .frame(width: 17, height: 17)
            .rotationEffect(.degrees(spin ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 0.85).repeatForever(autoreverses: false)) {
                    spin = true
                }
            }
    }
}

// Simple test function to verify translation API
func testTranslation(images: [UIImage], authService: AuthService) {
    print("🧪 === TRANSLATION TEST START ===")
    print("📸 Number of images to translate: \(images.count)")
    
    let translationService = TranslationService(authService: authService)
    
    // Test with first image only for sanity check
    if let firstImage = images.first {
        let authToken = authService.getAuthToken()
        let userID = authService.currentUserID

        Task {
            let targetLanguage = await UserLanguagePreferences.resolveMenuLanguage(
                authToken: authToken,
                userID: userID
            )

            print("🔄 Testing translation with first image to \(targetLanguage)...")
            translationService.translateImage(image: firstImage, targetLanguage: targetLanguage) { result in
                switch result {
                case .success(let response):
                    print("✅ TRANSLATION TEST SUCCESS!")
                    print("🆔 Image ID: \(response.imageId)")
                    print("📦 Found \(response.boxes.count) text boxes")
                    print("⏱️ Processing time: \(response.processingTime)s")
                    
                    // Show first few translations as summary
                    for (index, box) in response.boxes.prefix(3).enumerated() {
                        print("📝 Box \(index + 1): \(box.originalText) → \(box.translatedText)")
                    }
                    if response.boxes.count > 3 {
                        print("... and \(response.boxes.count - 3) more translations")
                    }
                case .failure(let error):
                    print("❌ TRANSLATION TEST FAILED: \(error.localizedDescription)")
                }
                print("🧪 === TRANSLATION TEST END ===")
            }
        }
    } else {
        print("❌ No images available for translation test")
        print("🧪 === TRANSLATION TEST END ===")
    }
}

struct ButtonsAtTop: View {
    let dismiss: DismissAction
    let onReTake: () -> Void
    var body: some View {
        HStack {
            PlatyIconButton(systemName: "chevron.left", size: 52) {
                onReTake()
                dismiss()
            }

            Spacer()

            Text("Preview")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.46))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 24)
        .padding(.top, 58)
    }
}

struct PhotoPreviewPage: View {
    @State var image: UIImage
    @StateObject var tm: TranslationModel = translationModelGlobal
    @ObservedObject var vm: CameraViewModel
    @ObservedObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss
    @State private var imageSettled = false
    
    init(image: UIImage, vm: CameraViewModel, authService: AuthService) {
        self.image = image
        self.vm = vm
        self.authService = authService
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                PlatyTheme.background.ignoresSafeArea()

                // The captured photo "lands" into place: slight scale-down
                // settle instead of the old fade+slide double animation.
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .shadow(color: .black.opacity(0.45), radius: 26, y: 12)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 104)
                    .scaleEffect(imageSettled ? 1 : 1.05)
                    .opacity(imageSettled ? 1 : 0)

                VStack {
                    ButtonsAtTop(dismiss: dismiss, onReTake: {
                        if !vm.capturedImages.isEmpty {
                            vm.capturedImages.removeLast()
                        }
                    })

                    Spacer()

                    HStack(spacing: 16) {
                        Button(action: {
                            dismiss()
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "plus")
                                Text("Add Page")
                            }
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(height: 52)
                            .padding(.horizontal, 18)
                            .background(PlatyTheme.surfaceRaised)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(PlatyTheme.border, lineWidth: 1))
                        }
                        .buttonStyle(PlatyPressStyle())

                        Spacer()

                        DoneButton(images: vm.capturedImages, authService: authService)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 44)
                    .platyEntrance(delay: 0.08)
                }
            }
        }
        .onAppear {
            withAnimation(PlatyMotion.softSpring.delay(0.04)) {
                imageSettled = true
            }
        }
    }
}
