import Foundation
import UIKit
class CameraViewModel: ObservableObject {
    @Published var capturedImages: [UIImage] = []
    @Published var showPreview: Bool = false
}
