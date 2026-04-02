import AVFoundation
import Flutter
import UIKit

private final class PreviewContainerView: UIView {
  var previewLayer: AVCaptureVideoPreviewLayer?

  override func layoutSubviews() {
    super.layoutSubviews()
    previewLayer?.frame = bounds
  }
}

final class RecorderPreviewPlatformViewFactory: NSObject, FlutterPlatformViewFactory {
  private weak var bridge: RecorderFlutterBridge?

  init(bridge: RecorderFlutterBridge) {
    self.bridge = bridge
    super.init()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    RecorderPreviewPlatformView(frame: frame, bridge: bridge)
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

final class RecorderPreviewPlatformView: NSObject, FlutterPlatformView {
  private let container = PreviewContainerView()
  private let previewLayer = AVCaptureVideoPreviewLayer()
  private weak var bridge: RecorderFlutterBridge?
  private weak var attachedSession: AVCaptureSession?

  init(frame: CGRect, bridge: RecorderFlutterBridge?) {
    self.bridge = bridge
    super.init()

    container.backgroundColor = .black
    container.frame = frame

    previewLayer.videoGravity = .resizeAspectFill
    previewLayer.frame = frame
    container.layer.addSublayer(previewLayer)
    container.previewLayer = previewLayer

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleSessionChanged),
      name: RecorderFlutterBridge.sessionDidChangeNotification,
      object: nil
    )

    bridge?.ensurePreviewReady()
    refreshSession()
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  func view() -> UIView {
    container
  }

  @objc private func handleSessionChanged() {
    refreshSession()
  }

  private func refreshSession() {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      let nextSession = self.bridge?.currentCaptureSession()
      if self.attachedSession === nextSession {
        return
      }

      // Avoid sporadic internal detach assertion by explicitly clearing old session first.
      self.previewLayer.session = nil
      self.attachedSession = nil

      if let nextSession = nextSession {
        self.previewLayer.session = nextSession
        self.attachedSession = nextSession
      }
    }
  }
}
