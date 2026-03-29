import Flutter
import Foundation

/// 将 `SlamRecordingSession` 接到 Flutter `MethodChannel`。
final class RecorderFlutterBridge {
  private let messenger: FlutterBinaryMessenger
  private var session: SlamRecordingSession?
  private var lastCompletedSessionPath: String?

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
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

      let url = URL(fileURLWithPath: path, isDirectory: true)
      let s = SlamRecordingSession(outputDirectory: url)
      s.start { [weak self] error in
        if let error = error {
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
        self?.session = nil
        switch res {
        case .success(let url):
          self?.lastCompletedSessionPath = url.path
          result(url.path)
        case .failure(let err):
          result(
            FlutterError(
              code: "stop_failed",
              message: err.localizedDescription,
              details: nil
            )
          )
        }
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
