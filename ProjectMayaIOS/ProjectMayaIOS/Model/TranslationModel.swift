import Combine
import SwiftUI

class TranslationModel: ObservableObject {
    @Published var imageList: [MenuImage] = []
    @Published var blockList: [MenuBlocks] = []
    var images: [UIImage] = []
    @Published var isTranslating: Bool = false
    private var vm: CameraViewModel = vmGlobal
    private var cancellables: Set<AnyCancellable> = Set<AnyCancellable>()
    @Published var isDataReady: Bool = false
    func getTranslation() {
        print("pushing")
        isTranslating = true
        translationApi(imageList: images) { imagelist, blocklist in
            print("translating")
            DispatchQueue.main.async {
                self.isTranslating = false
                if let imagelist = imagelist, let blocklist = blocklist {
                    self.imageList = imagelist
                    self.blockList = blocklist
                    self.isDataReady = true
                }
            }
        }
    }
    init() {
        vm.$capturedImages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newValue in
                guard let self = self else { return }
                print("vmGlobal.capturedImages changed:", newValue)
                self.images = newValue
            }
            .store(in: &cancellables)
    }
}
