import SwiftUI
import UIKit
import AVFoundation
import Combine

/// Base class for camera services
class CameraService: NSObject, ObservableObject {
    @Published var latestPhoto: UIImage?
    @Published var isTorchOn = false
    private(set) var session: AVCaptureSession = AVCaptureSession()
    func start() async throws {
        fatalError("Subclasses must implement start()")
    }

    func capture() {
        fatalError("Subclasses must implement capture()")
    }

    /// Toggle the torch. Base implementation just tracks state (stub/simulator);
    /// `RealCameraService` drives the actual hardware.
    func setTorch(_ on: Bool) {
        isTorchOn = on
    }
}
