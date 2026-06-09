import SwiftUI
import Foundation

class OCROverlayViewModel: ObservableObject {
    @Published var scale: CGFloat = 1.0
    @Published var offset: CGSize = .zero
    /// True while a pinch is in flight. The label layer hides itself during
    /// the gesture so we don't re-measure every label on every frame.
    @Published var isPinching = false
    /// True when zoomed past the fitted scale (used to lock page swiping).
    @Published var isZoomedIn = false

    private var lastScale: CGFloat = 1.0
    private var lastOffset: CGSize = .zero
    private var minimumScale: CGFloat = 1.0
    private var fittedScale: CGFloat = 1.0
    
    // MARK: - Container Properties
    private let originalWidth: CGFloat
    private let originalHeight: CGFloat
    
    init(originalWidth: CGFloat, originalHeight: CGFloat) {
        self.originalWidth = originalWidth
        self.originalHeight = originalHeight
    }
    
    // MARK: - Image Sizing Calculations
    func calculateImageLayout(containerSize: CGSize) -> ImageLayout {
        let baseScaleX = containerSize.width / originalWidth
        let baseScaleY = containerSize.height / originalHeight
        let baseScale = min(baseScaleX, baseScaleY)
        
        let displayWidth = originalWidth * baseScale
        let displayHeight = originalHeight * baseScale
        
        // Center the fitted image without cropping any edge.
        let imageOffsetX = (containerSize.width - displayWidth) / 2
        let imageOffsetY = (containerSize.height - displayHeight) / 2
        
        return ImageLayout(
            displayWidth: displayWidth,
            displayHeight: displayHeight,
            baseScale: baseScale,
            imageOffsetX: imageOffsetX,
            imageOffsetY: imageOffsetY,
            containerSize: containerSize
        )
    }
    
    // MARK: - Text Block Positioning
    func calculateBlockPosition(for block: TextBlock, layout: ImageLayout) -> BlockPosition {
        let rect = baseTextRect(for: block, layout: layout)
        let positionX = rect.midX
        let positionY = rect.midY
        
        return BlockPosition(
            x: positionX,
            y: positionY,
            width: rect.width,
            height: rect.height
        )
    }
    
    // MARK: - Coordinate Transformation for Unscaled Text Layer
    func calculateTransformedTextPosition(for block: TextBlock, layout: ImageLayout, containerSize: CGSize) -> TransformedTextPosition {
        transformedTextPosition(
            for: block,
            layout: layout,
            containerSize: containerSize,
            scale: scale,
            offset: offset
        )
    }
    
    // MARK: - Gesture Handling
    func handleMagnificationGesture(value: MagnificationGesture.Value, containerSize: CGSize) {
        if !isPinching {
            isPinching = true
        }
        let newScale = lastScale * value
        scale = max(minimumScale, min(8.0, newScale))
    }

    func endMagnificationGesture(containerSize: CGSize) {
        // Apply constraints when scale gesture ends
        constrainImagePosition(containerSize: containerSize)
        lastScale = scale
        lastOffset = offset
        isPinching = false
        updateZoomState()
    }
    
    func handleDragGesture(value: DragGesture.Value, containerSize: CGSize) {
        let newOffsetX = lastOffset.width + value.translation.width
        let newOffsetY = lastOffset.height + value.translation.height
        
        // Set new offset - let it follow finger freely during drag
        offset = CGSize(width: newOffsetX, height: newOffsetY)
    }
    
    func endDragGesture(containerSize: CGSize) {
        // Apply constraints when drag ends to snap to valid bounds
        constrainImagePosition(containerSize: containerSize)
        lastOffset = offset
    }
    
    func handleDoubleTap(containerSize: CGSize) {
        withAnimation(.easeInOut(duration: 0.3)) {
            if scale > fittedScale + 0.1 {
                scale = fittedScale
                lastScale = fittedScale
                offset = .zero
                lastOffset = .zero
            } else {
                scale = max(2.0, fittedScale * 2.0)
                lastScale = scale
            }
            
            // Apply central constraint system
            constrainImagePosition(containerSize: containerSize)
            updateZoomState()
        }
    }

    private func updateZoomState() {
        let zoomed = scale > minimumScale + 0.01
        if zoomed != isZoomedIn {
            isZoomedIn = zoomed
        }
    }
    
    // MARK: - Central Constraint System
    func constrainImagePosition(containerSize: CGSize) {
        let layout = calculateImageLayout(containerSize: containerSize)
        
        // Calculate the actual bounds of the scaled image
        let scaledImageWidth = layout.displayWidth * scale
        let scaledImageHeight = layout.displayHeight * scale
        
        let maxOffsetX = abs(scaledImageWidth - containerSize.width) / 2
        let maxOffsetY = abs(scaledImageHeight - containerSize.height) / 2
        
        // Constrain current offset to valid bounds
        offset = CGSize(
            width: max(-maxOffsetX, min(maxOffsetX, offset.width)),
            height: max(-maxOffsetY, min(maxOffsetY, offset.height))
        )
        
        // Update last offset to match constrained position
        lastOffset = offset
    }
    
    func resetZoomAndPan(blocks: [TextBlock] = [], containerSize: CGSize? = nil) {
        guard let containerSize, containerSize.width > 1, containerSize.height > 1 else {
            scale = 1.0
            lastScale = 1.0
            minimumScale = 1.0
            fittedScale = 1.0
            offset = .zero
            lastOffset = .zero
            return
        }

        let fillScale = fullscreenFillScale(containerSize: containerSize)
        scale = fillScale
        fittedScale = fillScale
        minimumScale = fillScale
        offset = .zero
        lastScale = fillScale
        lastOffset = .zero
        constrainImagePosition(containerSize: containerSize)
        updateZoomState()
    }

    private func fullscreenFillScale(containerSize: CGSize) -> CGFloat {
        let layout = calculateImageLayout(containerSize: containerSize)
        guard layout.displayWidth > 0, layout.displayHeight > 0 else {
            return 1.0
        }

        return max(
            1.0,
            max(
                containerSize.width / layout.displayWidth,
                containerSize.height / layout.displayHeight
            )
        )
    }

    private func baseTextRect(for block: TextBlock, layout: ImageLayout) -> CGRect {
        guard block.box2D.count >= 4 else {
            return .zero
        }

        let y0 = min(block.box2D[0], block.box2D[2]) * layout.baseScale + layout.imageOffsetY
        let y1 = max(block.box2D[0], block.box2D[2]) * layout.baseScale + layout.imageOffsetY
        let x0 = min(block.box2D[1], block.box2D[3]) * layout.baseScale + layout.imageOffsetX
        let x1 = max(block.box2D[1], block.box2D[3]) * layout.baseScale + layout.imageOffsetX

        return CGRect(
            x: x0,
            y: y0,
            width: max(1, x1 - x0 + 1),
            height: max(1, y1 - y0 + 1)
        )
    }

    private func transformedTextPosition(
        for block: TextBlock,
        layout: ImageLayout,
        containerSize: CGSize,
        scale: CGFloat,
        offset: CGSize
    ) -> TransformedTextPosition {
        let rect = baseTextRect(for: block, layout: layout)
        let imageRelativeX = rect.midX - containerSize.width / 2
        let imageRelativeY = rect.midY - containerSize.height / 2

        return TransformedTextPosition(
            x: (imageRelativeX * scale) + offset.width + containerSize.width / 2,
            y: (imageRelativeY * scale) + offset.height + containerSize.height / 2,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }

}

// MARK: - Supporting Data Structures
struct ImageLayout {
    let displayWidth: CGFloat
    let displayHeight: CGFloat
    let baseScale: CGFloat
    let imageOffsetX: CGFloat
    let imageOffsetY: CGFloat
    let containerSize: CGSize
}

struct BlockPosition {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
}

struct TransformedTextPosition {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
}
