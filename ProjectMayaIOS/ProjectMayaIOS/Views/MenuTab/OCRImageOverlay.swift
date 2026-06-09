//
//  menu_view.swift
//  practice
//
//  Created by Herrys Yu on 5/21/25.
//
import SwiftUI

private struct SelectedDish: Identifiable {
    let id = UUID()
    let translated: String
    let original: String
}

// Core OCR overlay functionality
private struct OCRImageOverlayCore: View {
    let image: UIImage
    let originalWidth: CGFloat
    let originalHeight: CGFloat
    let blocks: [TextBlock]
    let authService: AuthService
    @Binding var selectedDish: SelectedDish?
    var onZoomChange: ((Bool) -> Void)? = nil
    @StateObject private var viewModel: OCROverlayViewModel
    @State private var labelsVisible = false

    init(image: UIImage, originalWidth: CGFloat, originalHeight: CGFloat, blocks: [TextBlock], authService: AuthService, selectedDish: Binding<SelectedDish?>, onZoomChange: ((Bool) -> Void)? = nil) {
        self.image = image
        self.originalWidth = originalWidth
        self.originalHeight = originalHeight
        self.blocks = blocks
        self.authService = authService
        self._selectedDish = selectedDish
        self.onZoomChange = onZoomChange
        self._viewModel = StateObject(wrappedValue: OCROverlayViewModel(originalWidth: originalWidth, originalHeight: originalHeight))
    }
    
    var body: some View {
        GeometryReader { geometry in
            let containerSize = CGSize(width: geometry.size.width, height: geometry.size.height)
            let layout = viewModel.calculateImageLayout(containerSize: containerSize)

            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: layout.displayWidth, height: layout.displayHeight)
                    .position(
                        x: layout.imageOffsetX + layout.displayWidth / 2,
                        y: layout.imageOffsetY + layout.displayHeight / 2
                    )
                .clipped()
                .scaleEffect(viewModel.scale)
                .offset(viewModel.offset)
                .gesture(
                    SimultaneousGesture(
                        // Zoom gesture
                        MagnificationGesture()
                            .onChanged { value in
                                viewModel.handleMagnificationGesture(value: value, containerSize: containerSize)
                            }
                            .onEnded { _ in
                                viewModel.endMagnificationGesture(containerSize: containerSize)
                            },
                        DragGesture()
                            .onChanged { value in
                                viewModel.handleDragGesture(value: value, containerSize: containerSize)
                            }
                            .onEnded { _ in
                                viewModel.endDragGesture(containerSize: containerSize)
                            }
                    )
                )
                .onTapGesture(count: 2) {
                    viewModel.handleDoubleTap(containerSize: containerSize)
                }

                // Unscaled text overlay layer. Removed entirely while pinching:
                // re-measuring every label per gesture frame is what made zoom
                // feel janky, and the image transform alone runs on the GPU.
                if !viewModel.isPinching {
                    ZStack {
                        ForEach(Array(visibleLabelItems(layout: layout, containerSize: containerSize).enumerated()), id: \.element.index) { order, item in
                            let index = item.index
                            let block: TextBlock = blocks[index]
                            let transformedPosition = item.position

                            let displayText = (block.translatedText?.isEmpty == false ? block.translatedText! : block.text)
                            let cleanedDisplayText = displayText.trimmingCharacters(in: .whitespacesAndNewlines)

                            RotatedTextBox(
                                text: cleanedDisplayText,
                                angle: .radians(Double(block.angle) * .pi / 180),
                                height: transformedPosition.height,
                                width: transformedPosition.width,
                                scale: viewModel.scale,
                                onSelect: { translated in
                                    let cleanedTranslated = translated.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !cleanedTranslated.isEmpty else { return }
                                    selectedDish = SelectedDish(translated: cleanedTranslated, original: block.text)
                                }
                            )
                            .position(x: transformedPosition.x, y: transformedPosition.y)
                            .opacity(labelsVisible ? 1 : 0)
                            .scaleEffect(labelsVisible ? 1 : 0.88)
                            .animation(
                                PlatyMotion.softSpring.delay(min(Double(order) * 0.012, 0.22)),
                                value: labelsVisible
                            )
                        }
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.14), value: viewModel.isPinching)
            .onChange(of: viewModel.isZoomedIn) { _, zoomed in
                onZoomChange?(zoomed)
            }
            .onAppear {
                viewModel.resetZoomAndPan(blocks: blocks, containerSize: containerSize)
                revealLabels()
            }
            .onChange(of: blocks.count) { _, _ in
                withAnimation(PlatyMotion.softSpring) {
                    viewModel.resetZoomAndPan(blocks: blocks, containerSize: containerSize)
                }
                revealLabels()
            }
        }
    }

    private func visibleLabelItems(layout: ImageLayout, containerSize: CGSize) -> [OverlayLabelItem] {
        var accepted: [OverlayLabelItem] = []

        for index in blocks.indices {
            let block = blocks[index]
            let position = viewModel.calculateTransformedTextPosition(for: block, layout: layout, containerSize: containerSize)
            let displayText = (block.translatedText?.isEmpty == false ? block.translatedText! : block.text)
            let cleanedDisplayText = displayText.trimmingCharacters(in: .whitespacesAndNewlines)

            guard shouldRenderLabel(text: cleanedDisplayText, position: position, containerSize: containerSize) else {
                continue
            }

            let labelSize = RotatedTextBox.preferredSize(for: cleanedDisplayText, boxWidth: position.width, boxHeight: position.height, scale: viewModel.scale)
            let frame = CGRect(
                x: position.x - labelSize.width / 2,
                y: position.y - labelSize.height / 2,
                width: labelSize.width,
                height: labelSize.height
            )
            .insetBy(dx: -3, dy: -3)

            accepted.append(OverlayLabelItem(index: index, position: position, frame: frame))
        }

        return accepted
    }

    private func revealLabels() {
        labelsVisible = false
        DispatchQueue.main.async {
            withAnimation(PlatyMotion.softSpring) {
                labelsVisible = true
            }
        }
    }

    private func shouldRenderLabel(text: String, position: TransformedTextPosition, containerSize: CGSize) -> Bool {
        guard !text.isEmpty else { return false }

        let punctuation = CharacterSet.punctuationCharacters.union(.symbols).union(.whitespacesAndNewlines)
        let meaningful = text.unicodeScalars.contains { scalar in
            !punctuation.contains(scalar)
        }
        return meaningful
    }
}

private struct OverlayLabelItem {
    let index: Int
    let position: TransformedTextPosition
    let frame: CGRect
}

// Content without the order button for use in MenuPage
struct OCRImageOverlayContent: View {
    let image: UIImage
    let originalWidth: CGFloat
    let originalHeight: CGFloat
    let blocks: [TextBlock]
    let authService: AuthService
    var onZoomChange: ((Bool) -> Void)? = nil
    @State private var selectedDish: SelectedDish?

    var body: some View {
        OCRImageOverlayCore(
            image: image,
            originalWidth: originalWidth,
            originalHeight: originalHeight,
            blocks: blocks,
            authService: authService,
            selectedDish: $selectedDish,
            onZoomChange: onZoomChange
        )
        .sheet(item: $selectedDish) { selected in
            DishDetailView(translatedName: selected.translated, originalName: selected.original, authService: authService)
        }
    }
}

#Preview {
    let sampleImage = UIImage(named: "menu") ?? UIImage(systemName: "photo")!
    let sampleBlocks = [
        TextBlock(
            text: "特色卤面",
            angle: 0.0,
            box2D: [149, 702, 200, 903],
            translatedText: "Special Braised Noodles"
        ),
        TextBlock(
            text: "剁椒鱼头", 
            angle: 0.0,
            box2D: [149, 1142, 200, 1349],
            translatedText: "Chopped Chili Fish Head"
        ),
        TextBlock(
            text: "红烧排骨饭",
            angle: 0.0,
            box2D: [482, 271, 517, 448],
            translatedText: "Braised Pork Rib Rice"
        ),
        TextBlock(
            text: "海鲜炒米粉-",
            angle: 0.0,
            box2D: [504, 702, 545, 875],
            translatedText: "Seafood Fried Rice Noodles"
        ),
        TextBlock(
            text: "铁板田鸡",
            angle: 0.0,
            box2D: [149, 700, 200, 1050],
            translatedText: "Sizzling Frog"
        ),
        TextBlock(
            text: "扬州炒饭",
            angle: 0.0,
            box2D: [154, 1142, 193, 1345],
            translatedText: "Yangzhou Fried Rice"
        )
    ]
    
    OCRImageOverlayContent(
        image: sampleImage,
        originalWidth: 2000,
        originalHeight: 1125,
        blocks: sampleBlocks,
        authService: AuthService()
    )
    .environmentObject(OrderManager())
}
