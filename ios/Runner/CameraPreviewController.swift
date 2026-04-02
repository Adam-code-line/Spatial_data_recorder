import AVFoundation
import Foundation

final class CameraPreviewController {
  private let queue = DispatchQueue(label: "com.binwu.reconstruction.spatial_data_recorder.preview")
  private var session: AVCaptureSession?

  func currentSession() -> AVCaptureSession? {
    queue.sync { session }
  }

  func stop() {
    queue.sync {
      session?.stopRunning()
      session = nil
    }
  }

  func start(requestPermission: Bool, completion: @escaping (Bool) -> Void) {
    let status = AVCaptureDevice.authorizationStatus(for: .video)
    switch status {
    case .authorized:
      startAuthorized(completion: completion)
    case .notDetermined where requestPermission:
      AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
        guard granted, let self = self else {
          completion(false)
          return
        }
        self.startAuthorized(completion: completion)
      }
    default:
      completion(false)
    }
  }

  private func startAuthorized(completion: @escaping (Bool) -> Void) {
    queue.async { [weak self] in
      guard let self = self else {
        completion(false)
        return
      }

      if self.session == nil {
        let newSession = AVCaptureSession()
        newSession.beginConfiguration()
        if newSession.canSetSessionPreset(.high) {
          newSession.sessionPreset = .high
        }

        guard
          let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
          let input = try? AVCaptureDeviceInput(device: device),
          newSession.canAddInput(input)
        else {
          newSession.commitConfiguration()
          completion(false)
          return
        }

        newSession.addInput(input)
        newSession.commitConfiguration()
        self.session = newSession
      }

      self.session?.startRunning()
      completion(true)
    }
  }
}
