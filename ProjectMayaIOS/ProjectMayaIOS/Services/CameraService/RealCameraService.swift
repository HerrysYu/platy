import SwiftUI
import AVFoundation
import Photos
import Combine

/// Handles all AVCaptureSession plumbing.
/// - Not marked `@MainActor`, because AVFoundation delivers its
///   delegate callbacks on background queues.
/// - UI-facing state (`latestPhoto`) is pushed back to the main actor
///   with `Task { @MainActor in … }`.
final class RealCameraService: CameraService {

    // MARK: - Types
    enum CameraError: Error { case authorization, configuration, capture }

    // MARK: - Private
    private let output = AVCapturePhotoOutput()
    private let queue  = DispatchQueue(label: "camera.queue", qos: .userInitiated)

    // MARK: - Life-cycle ----------------------------------------------------

    /// Ask for permission, configure the pipeline on our private queue,
    /// then start the session.
    override func start() async throws {
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            throw CameraError.authorization
        }

        queue.async { [self] in
            configureSession()
            session.startRunning()      // must be **after** commitConfiguration()
        }
    }

    /// Configure inputs / outputs (runs only on `queue`).
    private func configureSession() {
        session.beginConfiguration()
        defer {
            session.sessionPreset = .hd1920x1080
            session.commitConfiguration() }

        // 1. Input ---------------------------------------------------------
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                 for: .video,
                                                 position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else { return }

        session.addInput(input)

        // 2. Output --------------------------------------------------------
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
    }

    // MARK: - Public API ----------------------------------------------------

    override func capture() {
        let settings = AVCapturePhotoSettings()
        output.capturePhoto(with: settings, delegate: self)
    }

    override func setTorch(_ on: Bool) {
        queue.async { [self] in
            guard
                let device = session.inputs
                    .compactMap({ ($0 as? AVCaptureDeviceInput)?.device })
                    .first(where: { $0.hasTorch })
            else { return }

            do {
                try device.lockForConfiguration()
                device.torchMode = on ? .on : .off
                device.unlockForConfiguration()
                Task { @MainActor in self.isTorchOn = on }
            } catch {
                print("⚠️ Torch configuration failed: \(error)")
            }
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate -------------------------------------

extension RealCameraService: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {

        guard
            error == nil,
            let data = photo.fileDataRepresentation(),
            let image = UIImage(data: data)
        else { return }

        // hop back to the main actor to update UI state
        Task { @MainActor in
            self.latestPhoto = image
        }
    }
} 