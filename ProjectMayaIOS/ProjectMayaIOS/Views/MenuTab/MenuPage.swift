import SwiftUI

struct MenuPage: View {
    @State var menuImageList: [MenuImage]
    @State var menuBlocksList: [MenuBlocks]
    let authService: AuthService
    var saveOnAppear = true
    @State private var currentPage: Int = 0
    @EnvironmentObject private var orderManager: OrderManager
    @State private var showOrderList = false
    @State private var showComboRecommendation = false
    @State private var navigateToRoot = false
    @State private var chromeVisible = false
    @State private var isZoomedIn = false

    private var validPages: [Int] {
        menuImageList.indices.filter { index in
            index < menuBlocksList.count
            && menuImageList[index].isValid()
            && menuBlocksList[index].isValid()
            && menuBlocksList[index].blockList.blocks != nil
        }
    }

    var body: some View {
        ZStack {
            PlatyTheme.background.ignoresSafeArea()

            if validPages.isEmpty {
                emptyState
            } else {
                TabView(selection: $currentPage) {
                    ForEach(validPages, id: \.self) { index in
                        OCRImageOverlayContent(
                            image: menuImageList[index].image,
                            originalWidth: menuImageList[index].width,
                            originalHeight: menuImageList[index].height,
                            blocks: menuBlocksList[index].blockList.blocks ?? [],
                            authService: authService,
                            onZoomChange: { zoomed in
                                isZoomedIn = zoomed
                            }
                        )
                        .tag(index)
                        .ignoresSafeArea()
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                // While zoomed in, panning the image must not flip pages.
                .scrollDisabled(isZoomedIn)
                .animation(PlatyMotion.softSpring, value: currentPage)

                VStack {
                    topBar
                        .padding(.horizontal, 24)
                        .padding(.top, 58)
                        .opacity(chromeVisible ? 1 : 0)
                        .offset(y: chromeVisible ? 0 : -12)
                    Spacer()
                    bottomBar
                        .padding(.horizontal, 24)
                        .padding(.bottom, 32)
                        .opacity(chromeVisible ? 1 : 0)
                        .offset(y: chromeVisible ? 0 : 18)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $navigateToRoot) {
            LandingPage(authService: authService)
                .navigationBarBackButtonHidden(true)
        }
        .onAppear {
            if saveOnAppear {
                orderManager.saveMealToHistory()
            }
            if currentPage == 0, let first = validPages.first {
                currentPage = first
            }
            withAnimation(PlatyMotion.smooth.delay(0.08)) {
                chromeVisible = true
            }
        }
        .sheet(isPresented: $showOrderList) {
            NavigationStack {
                OrderListView()
            }
            .environmentObject(orderManager)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showComboRecommendation) {
            ComboRecommendationView(
                menuItems: comboMenuItems,
                authService: authService
            )
            .environmentObject(orderManager)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    /// Aggregate every scanned text block across pages into the menu-item list
    /// sent to the combo agent (deduped, punctuation-only lines dropped).
    private var comboMenuItems: [ComboMenuItem] {
        var seen = Set<String>()
        var items: [ComboMenuItem] = []

        for blocks in menuBlocksList {
            for block in blocks.blockList.blocks ?? [] {
                let name = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, !seen.contains(name) else { continue }

                let punctuation = CharacterSet.punctuationCharacters
                    .union(.symbols)
                    .union(.whitespacesAndNewlines)
                guard name.unicodeScalars.contains(where: { !punctuation.contains($0) }) else {
                    continue
                }

                seen.insert(name)
                let translated = block.translatedText?.trimmingCharacters(in: .whitespacesAndNewlines)
                items.append(
                    ComboMenuItem(
                        name: name,
                        translated: (translated?.isEmpty == false && translated != name) ? translated : nil
                    )
                )
                if items.count >= 120 { return items }
            }
        }

        return items
    }

    private var topBar: some View {
        HStack {
            Button(action: { navigateToRoot = true }) {
                HStack(spacing: 9) {
                    Image(systemName: "chevron.left")
                    Text("Home")
                }
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(PlatyTheme.textPrimary)
                .padding(.horizontal, 16)
                .frame(height: 48)
                .background(Color.black.opacity(0.68))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
            }
            .buttonStyle(PlatyPressStyle())

            Spacer()

            if validPages.count > 1 {
                Text("\(pageNumber) / \(validPages.count)")
                    .font(.system(size: 15, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundColor(PlatyTheme.textPrimary)
                    .padding(.horizontal, 14)
                    .frame(height: 42)
                    .background(Color.black.opacity(0.62))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
                    .contentTransition(.numericText())
            }
        }
        .platyEntrance()
    }

    private var bottomBar: some View {
        HStack {
            ComboAIButton {
                showComboRecommendation = true
            }

            Spacer()

            Button(action: { showOrderList = true }) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 27, weight: .heavy))
                        .foregroundColor(PlatyTheme.accentStrong)
                        .frame(width: 64, height: 64)
                        .background(Color.black.opacity(0.82))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 1))

                    if orderManager.totalCount > 0 {
                        Text("\(orderManager.totalCount)")
                            .font(.system(size: 12, weight: .heavy, design: .rounded).monospacedDigit())
                            .foregroundColor(.black)
                            .frame(minWidth: 23, minHeight: 23)
                            .background(PlatyTheme.accent)
                            .clipShape(Capsule())
                            .offset(x: 5, y: -4)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .buttonStyle(PlatyPressStyle(scale: 0.9))
            .animation(PlatyMotion.spring, value: orderManager.totalCount)
        }
        .platyEntrance(delay: 0.1)
    }

    private var pageNumber: Int {
        (validPages.firstIndex(of: currentPage) ?? 0) + 1
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 52, weight: .semibold))
                .foregroundColor(PlatyTheme.textSecondary)
            Text("No menu data")
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundColor(PlatyTheme.textPrimary)
        }
        .padding(28)
        .background(PlatyTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(PlatyTheme.border, lineWidth: 1)
        )
    }
}
