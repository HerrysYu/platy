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

            // Step 2: Send OCR results straight to translation.
            let translationService = TranslationService(authService: self.authService)
            print("🌐 Starting translation for image \(index + 1) to \(targetLanguage)...")

            translationService.processOCRResults(ocrImageResult: ocrImageResult, targetLanguage: targetLanguage) { result in
                switch result {
                case .success(let response):
                    print("✅ Image \(index + 1) translation SUCCESS - received \(response.boxes.count) translated boxes")
                    let menuBlock = self.convertOCRProcessingToMenuBlocks(result)
                    print("🎯 Image \(index + 1) final blocks: \(menuBlock.blockList.blocks?.count ?? 0)")
                    completion(menuImage, menuBlock)
                case .failure(let error):
                    print("❌ Image \(index + 1) translation FAILED: \(error.localizedDescription)")
                    let fallbackBlocks = self.convertOCRToMenuBlocks(ocrImageResult)
                    completion(menuImage, fallbackBlocks)
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

struct PhotoPreviewPage: View {
    @State var image: UIImage
    @StateObject var tm: TranslationModel = translationModelGlobal
    @ObservedObject var vm: CameraViewModel
    @ObservedObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss
    @State private var imageSettled = false
    @State private var selectedIndex = 0

    init(image: UIImage, vm: CameraViewModel, authService: AuthService) {
        self.image = image
        self.vm = vm
        self.authService = authService
    }

    /// The image currently shown large. Falls back to the passed-in capture
    /// if the index drifts out of range (e.g. right after a delete).
    private var currentImage: UIImage {
        guard vm.capturedImages.indices.contains(selectedIndex) else {
            return vm.capturedImages.last ?? image
        }
        return vm.capturedImages[selectedIndex]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PlatyTheme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, 24)
                        .padding(.top, 58)

                    // The captured photo "lands" into place.
                    Image(uiImage: currentImage)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                        .shadow(color: .black.opacity(0.45), radius: 26, y: 12)
                        .padding(.horizontal, 14)
                        .padding(.top, 18)
                        .id(selectedIndex)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        .scaleEffect(imageSettled ? 1 : 1.05)
                        .opacity(imageSettled ? 1 : 0)
                        .frame(maxHeight: .infinity)

                    thumbnailStrip

                    DoneButton(images: vm.capturedImages, authService: authService)
                        .padding(.top, 6)
                        .padding(.bottom, 40)
                        .platyEntrance(delay: 0.08)
                }
            }
        }
        .onAppear {
            selectedIndex = max(0, vm.capturedImages.count - 1)
            withAnimation(PlatyMotion.softSpring.delay(0.04)) {
                imageSettled = true
            }
        }
    }

    private var header: some View {
        HStack {
            PlatyIconButton(systemName: "chevron.left", size: 52) {
                dismiss()
            }

            Spacer()

            Text("\(vm.capturedImages.count) page\(vm.capturedImages.count == 1 ? "" : "s")")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.46))
                .clipShape(Capsule())
                .contentTransition(.numericText())
        }
    }

    private var thumbnailStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(vm.capturedImages.indices, id: \.self) { index in
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: vm.capturedImages[index])
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 72, height: 72)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(
                                        selectedIndex == index ? PlatyTheme.accent : PlatyTheme.border,
                                        lineWidth: selectedIndex == index ? 3 : 1
                                    )
                            )
                            .onTapGesture {
                                withAnimation(PlatyMotion.spring) {
                                    selectedIndex = index
                                }
                            }

                        Button {
                            deletePage(at: index)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.white, Color.black.opacity(0.65))
                        }
                        .offset(x: 7, y: -7)
                    }
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                }

                Button {
                    // Return to the camera to capture another page; the new
                    // shot re-presents this preview with the page appended.
                    dismiss()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(PlatyTheme.accent)
                        .frame(width: 72, height: 72)
                        .background(PlatyTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(PlatyTheme.border, lineWidth: 1)
                        )
                }
                .buttonStyle(PlatyPressStyle())
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .animation(PlatyMotion.softSpring, value: vm.capturedImages.count)
        }
    }

    private func deletePage(at index: Int) {
        withAnimation(PlatyMotion.spring) {
            guard vm.capturedImages.indices.contains(index) else { return }
            vm.capturedImages.remove(at: index)

            if vm.capturedImages.isEmpty {
                // Nothing left to preview: go back to the camera.
                dismiss()
                return
            }

            selectedIndex = min(selectedIndex, vm.capturedImages.count - 1)
        }
    }
}
