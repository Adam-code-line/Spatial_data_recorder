import AVFoundation
import Flutter
import Foundation
import UIKit

/// 将 `SlamRecordingSession` 接到 Flutter `MethodChannel`。
final class RecorderFlutterBridge {
  static let sessionDidChangeNotification = Notification.Name("RecorderSessionDidChangeNotification")

  private let messenger: FlutterBinaryMessenger
  private let previewController = CameraPreviewController()
  private var session: SlamRecordingSession?
  private var lastCompletedSessionPath: String?
  private var didConsumeWarmupTrial = false

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
  }

  private func notifySessionChanged() {
    DispatchQueue.main.async {
      NotificationCenter.default.post(name: Self.sessionDidChangeNotification, object: nil)
    }
  }

  private static func shouldTreatAsWarmupTrial(_ error: Error) -> Bool {
    guard let recordingError = error as? SlamRecordingError else { return false }
    guard case .writerSetupFailed(let message) = recordingError else { return false }
    return message.contains("domain=AVFoundationErrorDomain")
      && message.contains("code=-11800")
      && message.contains("underlyingCode=-12780")
  }

  func currentCaptureSession() -> AVCaptureSession? {
    session?.currentCaptureSession ?? previewController.currentSession()
  }

  func ensurePreviewReady() {
    guard session == nil else { return }
    previewController.start(requestPermission: false) { [weak self] ok in
      if ok {
        self?.notifySessionChanged()
      }
    }
  }

  func register() {
    let channel = FlutterMethodChannel(
      name: "com.binwu.reconstruction.spatial_data_recorder/recorder",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "preparePreview":
      previewController.start(requestPermission: true) { ok in
        if ok {
          self.notifySessionChanged()
        }
        result(nil)
      }

    case "getRecordingStatus":
      result([
        "recording": session != nil,
        "activeSessionPath": session?.outputDirectory.path,
        "lastCompletedSessionPath": lastCompletedSessionPath as Any,
      ])

    case "startRecording":
      guard session == nil else {
        result(
          FlutterError(
            code: "already_recording",
            message: SlamRecordingError.alreadyRecording.localizedDescription,
            details: nil
          )
        )
        return
      }
      guard let args = call.arguments as? [String: Any],
            let path = args["outputDir"] as? String
      else {
        result(
          FlutterError(code: "bad_args", message: "需要 outputDir: String", details: nil)
        )
        return
      }
      let enableAudio = (args["enableAudio"] as? Bool) ?? true

      let url = URL(fileURLWithPath: path, isDirectory: true)
      notifySessionChanged()
      previewController.stop()
      let s = SlamRecordingSession(outputDirectory: url, enableAudio: enableAudio)
      s.start { [weak self] error in
        if let error = error {
          self?.previewController.start(requestPermission: false) { ok in
            if ok {
              self?.notifySessionChanged()
            }
          }
          result(
            FlutterError(
              code: "start_failed",
              message: error.localizedDescription,
              details: nil
            )
          )
          return
        }
        self?.session = s
        self?.notifySessionChanged()
        result(nil)
      }

    case "stopRecording":
      guard let s = session else {
        result(
          FlutterError(
            code: "not_recording",
            message: "当前未在录制。",
            details: nil
          )
        )
        return
      }
      s.stop { [weak self] res in
        guard let self = self else { return }
        switch res {
        case .success(let url):
          self.session = nil
          self.notifySessionChanged()
          self.previewController.start(requestPermission: false) { [weak self] ok in
            if ok {
              self?.notifySessionChanged()
            }
          }
          self.lastCompletedSessionPath = url.path
          result(url.path)
        case .failure(let err):
          if !self.didConsumeWarmupTrial, Self.shouldTreatAsWarmupTrial(err) {
            self.didConsumeWarmupTrial = true
            self.session = nil
            self.notifySessionChanged()
            self.previewController.start(requestPermission: false) { [weak self] ok in
              if ok {
                self?.notifySessionChanged()
              }
            }
            try? FileManager.default.removeItem(at: s.outputDirectory)
            result("")
            return
          }

          // If native stop already tore down capture session, allow user to start
          // a new recording even when writer finalization failed.
          if s.currentCaptureSession == nil {
            self.session = nil
            self.notifySessionChanged()
            self.previewController.start(requestPermission: false) { [weak self] ok in
              if ok {
                self?.notifySessionChanged()
              }
            }
          } else {
            self.notifySessionChanged()
          }
          result(
            FlutterError(
              code: "stop_failed",
              message: err.localizedDescription,
              details: nil
            )
          )
        }
      }

    case "shareFile":
      guard let args = call.arguments as? [String: Any],
            let filePath = args["filePath"] as? String
      else {
        result(
          FlutterError(code: "bad_args", message: "需要 filePath: String", details: nil)
        )
        return
      }
      presentShareSheet(filePath: filePath, result: result)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func presentShareSheet(filePath: String, result: @escaping FlutterResult) {
    guard FileManager.default.fileExists(atPath: filePath) else {
      result(
        FlutterError(code: "file_not_found", message: "分享文件不存在", details: filePath)
      )
      return
    }

    DispatchQueue.main.async {
      guard let controller = self.topViewController() else {
        result(
          FlutterError(code: "no_view_controller", message: "无法打开分享面板", details: nil)
        )
        return
      }

      let url = URL(fileURLWithPath: filePath)
      let activityController = UIActivityViewController(
        activityItems: [url],
        applicationActivities: nil
      )
      if let popover = activityController.popoverPresentationController {
        popover.sourceView = controller.view
        popover.sourceRect = CGRect(
          x: controller.view.bounds.midX,
          y: controller.view.bounds.midY,
          width: 0,
          height: 0
        )
        popover.permittedArrowDirections = []
      }

      controller.present(activityController, animated: true) {
        result(nil)
      }
    }
  }

  private func topViewController() -> UIViewController? {
    let root = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }?
      .rootViewController

    var top = root
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }
}
