import SwiftUI
import UIKit

struct GradientOverlayView: View {
    var body: some View {
        LinearGradient(
            gradient: Gradient(colors: [Color.black.opacity(0.82), Color.black.opacity(0)]),
            startPoint: .top,
            endPoint: .bottom

        )
        .frame(height: 180)
    }
}

let vmGlobal: CameraViewModel = CameraViewModel()
struct CameraLandingScreen: View {
    @ObservedObject var vm: CameraViewModel = vmGlobal
    @StateObject var tm: TranslationModel = translationModelGlobal
    @ObservedObject var authService: AuthService
    @StateObject private var camera: CameraService = CameraServiceFactory.createSmartCameraService()
    @State private var showCamera: Bool = false
    @State private var newImage: UIImage?
    @State private var showGallery: Bool = false
    @State var menuImageList: [MenuImage] = []
    @State var menuBlocklList: [MenuBlocks] = []
    @State var showPhotoPreview: Bool = false
    @State var isDataReady: Bool = false
    @State var imageForPush: UIImage?
    @State private var focusPulse = false
    @State private var controlsVisible = false
    @State private var captureFlash = false

    var fontColor: Color = .white
    
    init(authService: AuthService) {
        self.authService = authService
    }
    var body: some View {
            ZStack {
                CameraView(service: camera)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    topBar
                        .padding(.horizontal, 24)
                        .padding(.top, 56)
                        .opacity(controlsVisible ? 1 : 0)
                        .offset(y: controlsVisible ? 0 : -12)

                    Spacer()

                    FocusFrame(isPulsing: focusPulse)
                        .aspectRatio(0.74, contentMode: .fit)
                        .padding(.horizontal, 30)
                        .opacity(controlsVisible ? 1 : 0)
                        .scaleEffect(controlsVisible ? 1 : 0.95)

                    Spacer()

                    bottomControls
                        .padding(.bottom, 34)
                        .background(
                            LinearGradient(
                                colors: [Color.black.opacity(0), Color.black.opacity(0.9)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .ignoresSafeArea()
                        )
                }
                .animation(PlatyMotion.smooth, value: controlsVisible)
                .sheet(isPresented: $vm.showPreview) {
                    PhotoSelectionPage(
                        vm: vm,
                        isDataReady: $isDataReady,
                        imageList: $menuImageList,
                        blockList: $menuBlocklList,
                        onAddPhoto: {
                            vm.showPreview = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                showGallery = true
                            }
                        }
                    )
                }
                .sheet(isPresented: $showGallery) {
                    ImagePicker(selectedImage: $newImage)
                }
                .fullScreenCover(isPresented: $showPhotoPreview) {
                    PhotoPreviewPage(image: imageForPush ?? UIImage(), vm: vm, authService: authService)
                }
                .onChange(of: newImage) { _, image in
                    guard let image else { return }
                    let preparedImage = ImageUtils.preparedForMenuAnalysis(image)
                    vm.capturedImages.append(preparedImage)
                    imageForPush = preparedImage
                    withAnimation(PlatyMotion.spring) {
                        showPhotoPreview = true
                    }
                    isDataReady = true
                    newImage = nil
                }
                .onChange(of: camera.latestPhoto) { _, image in
                    if let image: UIImage = image {
                        vm.capturedImages.append(ImageUtils.preparedForMenuAnalysis(image))
                        imageForPush = vm.capturedImages.last!
                        withAnimation(PlatyMotion.spring) {
                            showPhotoPreview = true
                        }
                        isDataReady = true
                    }
                }
                VStack {
                    GradientOverlayView()
                    Spacer()
                }
                .ignoresSafeArea()

                if captureFlash {
                    Color.white
                        .opacity(0.42)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeOut(duration: 0.18), value: captureFlash)
            .navigationDestination(isPresented: $tm.isDataReady) {
                MenuPage(menuImageList: tm.imageList, menuBlocksList: tm.blockList, authService: authService)
            }
            .task {
                try? await camera.start()
                controlsVisible = true
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                    focusPulse = true
                }
            }
    }

    private func capturePhoto() {
        withAnimation(.easeOut(duration: 0.08)) {
            captureFlash = true
        }

        camera.capture()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(.easeOut(duration: 0.24)) {
                captureFlash = false
            }
        }
    }

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text("Platy")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Menu Lens")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.white.opacity(0.62))
            }

            Spacer()
        }
    }

    private var bottomControls: some View {
        HStack(alignment: .center) {
            CameraToolButton(systemName: "photo.on.rectangle") {
                showGallery = true
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: {
                withAnimation(.spring(response: 0.18, dampingFraction: 0.62)) {
                    capturePhoto()
                }
            }) {
                ZStack {
                    Circle()
                        .stroke(Color.white, lineWidth: 4)
                        .frame(width: 82, height: 82)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 68, height: 68)
                    Circle()
                        .stroke(PlatyTheme.accent.opacity(0.9), lineWidth: focusPulse ? 2 : 0)
                        .frame(width: focusPulse ? 96 : 84, height: focusPulse ? 96 : 84)
                        .opacity(focusPulse ? 0 : 0.8)
                }
            }
            .buttonStyle(PlatyPressStyle(scale: 0.88))
            .frame(maxWidth: .infinity, alignment: .center)

            CameraToolButton(
                systemName: camera.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill",
                isActive: camera.isTorchOn
            ) {
                camera.setTorch(!camera.isTorchOn)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 30)
        .padding(.top, 36)
        .opacity(controlsVisible ? 1 : 0)
        .offset(y: controlsVisible ? 0 : 18)
    }
}

private struct CameraToolButton: View {
    let systemName: String
    var isActive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 25, weight: .bold))
                .foregroundStyle(isActive ? PlatyTheme.accent : .white)
                .frame(width: 64, height: 64)
                .background(Color.black.opacity(0.52))
                .clipShape(Circle())
                .overlay(
                    Circle().stroke(
                        isActive ? PlatyTheme.accent.opacity(0.6) : Color.white.opacity(0.16),
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(PlatyPressStyle(scale: 0.9))
        .animation(PlatyMotion.ease, value: isActive)
    }
}

private struct FocusFrame: View {
    let isPulsing: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
                .scaleEffect(isPulsing ? 1.02 : 0.99)
                .opacity(isPulsing ? 0.2 : 0.4)

            ForEach(FocusCorner.allCases) { corner in
                RoundedCorner(corner: corner)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    .frame(width: 72, height: 72)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: corner.alignment)
                    .shadow(color: .black.opacity(0.4), radius: 8)
            }
        }
    }
}

private enum FocusCorner: CaseIterable, Identifiable {
    case topLeading, topTrailing, bottomLeading, bottomTrailing

    var id: Self { self }

    var alignment: Alignment {
        switch self {
        case .topLeading: return .topLeading
        case .topTrailing: return .topTrailing
        case .bottomLeading: return .bottomLeading
        case .bottomTrailing: return .bottomTrailing
        }
    }
}

private struct RoundedCorner: Shape {
    let corner: FocusCorner

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let length = rect.width * 0.72

        switch corner {
        case .topLeading:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))
        case .topTrailing:
            path.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + length))
        case .bottomLeading:
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY - length))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + length, y: rect.maxY))
        case .bottomTrailing:
            path.move(to: CGPoint(x: rect.maxX - length, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
        }

        return path
    }
}
