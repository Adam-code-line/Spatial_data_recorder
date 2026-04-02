import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var recorderBridge: RecorderFlutterBridge?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let ok = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    if let controller = window?.rootViewController as? FlutterViewController {
      let bridge = RecorderFlutterBridge(messenger: controller.binaryMessenger)
      bridge.register()
      let factory = RecorderPreviewPlatformViewFactory(bridge: bridge)
      registrar(forPlugin: "RecorderPreviewPlatformView")?
        .register(factory, withId: "com.binwu.reconstruction.spatial_data_recorder/preview")
      recorderBridge = bridge
    }
    return ok
  }
}
