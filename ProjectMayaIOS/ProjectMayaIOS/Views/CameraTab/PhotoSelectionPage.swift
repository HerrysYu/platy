import SwiftUI

struct PhotoSelectionPage: View {
    @ObservedObject var vm: CameraViewModel
    @State private var isTranslating = false
    @State private var selectedIndex: Int = 0
    @Binding var isDataReady: Bool
    @Binding var imageList: [MenuImage]
    @Binding var blockList: [MenuBlocks]
    let onAddPhoto: () -> Void

    init(
        vm: CameraViewModel,
        isDataReady: Binding<Bool>,
        imageList: Binding<[MenuImage]>,
        blockList: Binding<[MenuBlocks]>,
        onAddPhoto: @escaping () -> Void = {}
    ) {
        self.vm = vm
        self._isDataReady = isDataReady
        self._imageList = imageList
        self._blockList = blockList
        self.onAddPhoto = onAddPhoto
    }

    func onDismiss() {
        vm.showPreview = false
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: {onDismiss()}) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(PlatyTheme.textPrimary)
                        .frame(width: 44, height: 44)
                        .background(PlatyTheme.surfaceRaised)
                        .clipShape(Circle())
                }
                
                Spacer()
                
                Text("Photo Preview")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(PlatyTheme.textPrimary)
                
                Spacer()
                
                Button(action: {onDismiss()}) {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(PlatyTheme.textPrimary)
                        .frame(width: 44, height: 44)
                        .background(PlatyTheme.surfaceRaised)
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 14)
            
            if !vm.capturedImages.isEmpty {
                Image(uiImage: vm.capturedImages[selectedIndex])
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 430)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .id(selectedIndex)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .animation(PlatyMotion.softSpring, value: selectedIndex)
            } else {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(PlatyTheme.surface)
                    .frame(height: 400)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 42))
                            .foregroundColor(PlatyTheme.textSecondary)
                    )
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(vm.capturedImages.indices, id: \.self) { index in
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: vm.capturedImages[index])
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 80, height: 80)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(selectedIndex == index ? PlatyTheme.accent : PlatyTheme.border, lineWidth: selectedIndex == index ? 3 : 1)
                                )
                                .scaleEffect(selectedIndex == index ? 1.03 : 1)
                                .platyShimmer(active: selectedIndex == index, duration: 2.3)
                                .onTapGesture {
                                    withAnimation(PlatyMotion.spring) {
                                        selectedIndex = index
                                    }
                                }
                            
                            Button(action: {
                                withAnimation(PlatyMotion.spring) {
                                    vm.capturedImages.remove(at: index)
                                    if vm.capturedImages.isEmpty {
                                        selectedIndex = 0
                                    } else if selectedIndex >= vm.capturedImages.count {
                                        selectedIndex = vm.capturedImages.count - 1
                                    }
                                }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.white)
                                    .background(Color.black.opacity(0.6))
                                    .clipShape(Circle())
                            }
                            .offset(x: 6, y: -6)
                        }
                        .transition(.scale(scale: 0.88).combined(with: .opacity))
                    }
                    
                    Button(action: {
                        onAddPhoto()
                    }) {
                        Image(systemName: "plus.square")
                            .font(.system(size: 32, weight: .bold))
                            .frame(width: 80, height: 80)
                            .foregroundColor(PlatyTheme.accent)
                            .background(PlatyTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(PlatyTheme.border, lineWidth: 1)
                            )
                    }
                    .buttonStyle(PlatyPressStyle())
                }
                .padding(.horizontal)
                .padding(.vertical, 18)
                .animation(PlatyMotion.softSpring, value: vm.capturedImages.count)
            }
            
            Spacer()
            
            PlatyPrimaryButton(
                title: isTranslating ? "Processing..." : "Done",
                systemImage: "checkmark",
                isLoading: isTranslating,
                isDisabled: isTranslating || vm.capturedImages.isEmpty
            ) {
                translateImages(images: vm.capturedImages)
            }
            .padding()
        }
        .background(PlatyTheme.background.ignoresSafeArea())
    }
    
    // Integrate Vision & translation here
    private func translateImages(images: [UIImage]) {
        onDismiss()
    }
}
