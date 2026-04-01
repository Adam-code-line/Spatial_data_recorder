import AVFoundation
import CoreMotion
import Darwin
import Foundation
import QuartzCore
import UIKit

enum SlamRecordingError: LocalizedError {
  case simulatorNotSupported
  case cameraPermissionDenied
  case captureSetupFailed
  case writerSetupFailed(String)
  case alreadyRecording

  var errorDescription: String? {
    switch self {
    case .simulatorNotSupported:
      return "SLAM 采集需要真机（相机与 IMU）。"
    case .cameraPermissionDenied:
      return "未授予相机权限。"
    case .captureSetupFailed:
      return "无法配置相机采集。"
    case .writerSetupFailed(let message):
      return "视频写入失败: \(message)"
    case .alreadyRecording:
      return "已在录制中。"
    }
  }
}

// MARK: - JSONL 缓冲（P1：停止时按 time 升序落盘）

/// 同一时间戳下的稳定次序：陀螺 → 加速度 →（可选）温度 → 视频帧。
private enum JsonlLineKind: Int {
  case gyroscope = 0
  case accelerometer = 1
  case imuTemperature = 2
  case frame = 3
}

private struct PendingJsonlLine {
  let time: Double
  let kind: JsonlLineKind
  let object: [String: Any]
}

/// P0 + P1：单目视频 + IMU；JSONL 内存缓冲、停止时按 `time` 排序写入；录制开始后锁定对焦/曝光；`calibration.json` 仍为占位内参。
///
/// 单位（与 Spectacular DATA_FORMAT 一致）：`gyroscope` 为 **rad/s**（`CMDeviceMotion.rotationRate`）；
/// `accelerometer` 为 **m/s²**，当前为 `gravity + userAcceleration`（含重力，与设备参考系一致）。
final class SlamRecordingSession: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
  let outputDirectory: URL

  private let syncQueue = DispatchQueue(label: "com.binwu.reconstruction.spatial_data_recorder.recording")
  private let videoQueue = DispatchQueue(label: "com.binwu.reconstruction.spatial_data_recorder.video")
  private let motionQueue = OperationQueue()

  private var captureSession: AVCaptureSession?
  private var captureDevice: AVCaptureDevice?
  private var videoOutput: AVCaptureVideoDataOutput?
  private var assetWriter: AVAssetWriter?
  private var videoInput: AVAssetWriterInput?

  private var pendingJsonl: [PendingJsonlLine] = []

  private let motionManager = CMMotionManager()

  /// 与首帧对齐后的单调时钟原点（秒，从 0 起算 IMU）
  private var timeOriginMedia: CFTimeInterval = 0
  private var firstVideoPts: CMTime?
  private var frameIndex: Int = 0
  private var videoWidth: Int = 0
  private var videoHeight: Int = 0

  private var isStopping = false
  private var didStartWriter = false

  init(outputDirectory: URL) {
    self.outputDirectory = outputDirectory
    motionQueue.name = "com.binwu.reconstruction.spatial_data_recorder.motion"
    motionQueue.maxConcurrentOperationCount = 1
  }

  func start(completion: @escaping (Error?) -> Void) {
    #if targetEnvironment(simulator)
    completion(SlamRecordingError.simulatorNotSupported)
    return
    #endif

    AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
      guard let self = self else { return }
      if !granted {
        DispatchQueue.main.async {
          completion(SlamRecordingError.cameraPermissionDenied)
        }
        return
      }
      self.syncQueue.async {
        self.configureCaptureAndRun(completion: completion)
      }
    }
  }

  private func configureCaptureAndRun(completion: @escaping (Error?) -> Void) {
    let session = AVCaptureSession()
    session.sessionPreset = .high

    guard
      let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
      let input = try? AVCaptureDeviceInput(device: device),
      session.canAddInput(input)
    else {
      DispatchQueue.main.async { completion(SlamRecordingError.captureSetupFailed) }
      return
    }
    session.addInput(input)
    captureDevice = device

    let output = AVCaptureVideoDataOutput()
    output.videoSettings = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
    ]
    output.alwaysDiscardsLateVideoFrames = true
    output.setSampleBufferDelegate(self, queue: videoQueue)

    guard session.canAddOutput(output) else {
      DispatchQueue.main.async { completion(SlamRecordingError.captureSetupFailed) }
      return
    }
    session.addOutput(output)

    if let conn = output.connection(with: .video), conn.isCameraIntrinsicMatrixDeliverySupported {
      conn.isCameraIntrinsicMatrixDeliveryEnabled = true
    }

    captureSession = session
    videoOutput = output

    session.startRunning()

    DispatchQueue.main.async { [weak self] in
      guard let self = self else {
        completion(nil)
        return
      }
      UIApplication.shared.isIdleTimerDisabled = true
      /// 短延迟后再锁定对焦/曝光，使 AE/AF 先收敛（见 `Flutter-iOS-SLAM数据采集应用开发指南` §4.1）。
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
        self?.applyFocusExposureLockIfPossible()
      }
      completion(nil)
    }
  }

  /// 对焦与曝光锁定（链式 completion）。白平衡在曝光完成后尽量锁定，减少录制中漂移。
  private func applyFocusExposureLockIfPossible() {
    guard let device = captureDevice else { return }

    let lensPosition = min(max(device.lensPosition, 0), 1)

    do {
      try device.lockForConfiguration()
      if device.isFocusPointOfInterestSupported {
        device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
      }
      if device.isExposurePointOfInterestSupported {
        device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
      }
      device.unlockForConfiguration()
    } catch {
      return
    }

    device.setFocusModeLocked(lensPosition: lensPosition) { [weak self] _ in
      guard let device = self?.captureDevice else { return }
      do {
        try device.lockForConfiguration()
        guard device.isExposureModeSupported(.custom) else {
          device.unlockForConfiguration()
          return
        }
        let duration = device.exposureDuration
        let iso = min(max(device.iso, device.activeFormat.minISO), device.activeFormat.maxISO)
        device.setExposureModeCustom(duration: duration, iso: iso) { _ in
          guard let device = self?.captureDevice else { return }
          do {
            try device.lockForConfiguration()
            if device.isWhiteBalanceModeSupported(.locked) {
              device.whiteBalanceMode = .locked
            }
            device.unlockForConfiguration()
          } catch {
            try? device.unlockForConfiguration()
          }
        }
      } catch {
        try? device.unlockForConfiguration()
      }
    }
  }

  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    syncQueue.async { [weak self] in
      self?.processVideoSampleBuffer(sampleBuffer)
    }
  }

  private func processVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
    guard !isStopping else { return }

    if assetWriter == nil {
      guard startWriterIfNeeded(with: sampleBuffer) else { return }
    }

    guard
      let input = videoInput,
      let writer = assetWriter,
      writer.status == .writing,
      input.isReadyForMoreMediaData
    else {
      return
    }

    if !didStartWriter {
      let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
      writer.startSession(atSourceTime: pts)
      firstVideoPts = pts
      timeOriginMedia = CACurrentMediaTime()
      startMotion()
      didStartWriter = true
      appendFrameJsonl(number: frameIndex, sampleBuffer: sampleBuffer)
      frameIndex += 1
      input.append(sampleBuffer)
      return
    }

    appendFrameJsonl(number: frameIndex, sampleBuffer: sampleBuffer)
    frameIndex += 1
    input.append(sampleBuffer)
  }

  private func startWriterIfNeeded(with sampleBuffer: CMSampleBuffer) -> Bool {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return false }
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    videoWidth = width
    videoHeight = height

    let movieURL = outputDirectory.appendingPathComponent("data.mov")
    try? FileManager.default.removeItem(at: movieURL)

    do {
      let writer = try AVAssetWriter(outputURL: movieURL, fileType: .mov)
      let videoSettings: [String: Any] = [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height,
        AVVideoCompressionPropertiesKey: [
          AVVideoAverageBitRateKey: width * height * 4,
          AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
          AVVideoMaxKeyFrameIntervalKey: 60,
        ] as [String: Any],
      ]

      let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
      input.expectsMediaDataInRealTime = true

      guard writer.canAdd(input) else {
        return false
      }
      writer.add(input)

      guard writer.startWriting() else {
        return false
      }

      assetWriter = writer
      videoInput = input
      return true
    } catch {
      return false
    }
  }

  private func startMotion() {
    guard motionManager.isDeviceMotionAvailable else { return }
    motionManager.deviceMotionUpdateInterval = 1.0 / 100.0
    motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: motionQueue) { [weak self] motion, _ in
      guard let self = self, let m = motion else { return }
      self.syncQueue.async {
        self.appendImuLines(from: m)
      }
    }
  }

  private func appendImuLines(from motion: CMDeviceMotion) {
    guard !isStopping, didStartWriter else { return }

    let t = CACurrentMediaTime() - timeOriginMedia
    let gx = motion.rotationRate.x
    let gy = motion.rotationRate.y
    let gz = motion.rotationRate.z

    let ax = motion.gravity.x + motion.userAcceleration.x
    let ay = motion.gravity.y + motion.userAcceleration.y
    let az = motion.gravity.z + motion.userAcceleration.z

    enqueueJsonl(
      time: t,
      kind: .gyroscope,
      object: [
        "time": t,
        "sensor": [
          "type": "gyroscope",
          "values": [gx, gy, gz],
        ],
      ]
    )
    enqueueJsonl(
      time: t,
      kind: .accelerometer,
      object: [
        "time": t,
        "sensor": [
          "type": "accelerometer",
          "values": [ax, ay, az],
        ],
      ]
    )
  }

  private func appendFrameJsonl(number: Int, sampleBuffer: CMSampleBuffer) {
    guard let first = firstVideoPts else { return }
    let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    let rel = CMTimeSubtract(pts, first)
    let t = CMTimeGetSeconds(rel)

    enqueueJsonl(
      time: t,
      kind: .frame,
      object: [
        "number": number,
        "time": t,
        "frames": [
          ["cameraInd": 0] as [String: Any],
        ],
      ]
    )
  }

  private func enqueueJsonl(time: Double, kind: JsonlLineKind, object: [String: Any]) {
    pendingJsonl.append(PendingJsonlLine(time: time, kind: kind, object: object))
  }

  /// P1：整段会话缓冲于内存，停止时按 `time` 升序、同类稳定次序一次写入（减少录制中频繁刷盘）。
  private func writeSortedJsonlToDisk() {
    guard !pendingJsonl.isEmpty else { return }
    let sorted = pendingJsonl.sorted { a, b in
      if a.time != b.time { return a.time < b.time }
      return a.kind.rawValue < b.kind.rawValue
    }
    let url = outputDirectory.appendingPathComponent("data.jsonl")
    try? FileManager.default.removeItem(at: url)
    var blob = Data()
    for line in sorted {
      guard JSONSerialization.isValidJSONObject(line.object),
            let data = try? JSONSerialization.data(withJSONObject: line.object, options: [.sortedKeys]),
            let s = String(data: data, encoding: .utf8)
      else {
        continue
      }
      if let nl = (s + "\n").data(using: .utf8) {
        blob.append(nl)
      }
    }
    try? blob.write(to: url, options: [.atomic])
    pendingJsonl.removeAll()
  }

  func stop(completion: @escaping (Result<URL, Error>) -> Void) {
    syncQueue.async { [weak self] in
      self?.performStop(completion: completion)
    }
  }

  private func performStop(completion: @escaping (Result<URL, Error>) -> Void) {
    isStopping = true
    motionManager.stopDeviceMotionUpdates()

    videoOutput?.setSampleBufferDelegate(nil, queue: nil)
    captureSession?.stopRunning()
    captureSession = nil
    videoOutput = nil
    captureDevice = nil

    writeSortedJsonlToDisk()

    let finalizeSuccess: () -> Void = { [weak self] in
      guard let self = self else { return }
      self.assetWriter = nil
      self.videoInput = nil

      self.writeCalibrationJson()
      self.writeMetadataJson()

      DispatchQueue.main.async {
        UIApplication.shared.isIdleTimerDisabled = false
        completion(.success(self.outputDirectory))
      }
    }

    if let input = videoInput, let writer = assetWriter, didStartWriter {
      input.markAsFinished()
      writer.finishWriting { [weak self] in
        guard let self = self else { return }
        self.syncQueue.async {
          if writer.status == .failed {
            self.assetWriter = nil
            self.videoInput = nil
            let err = writer.error ?? SlamRecordingError.writerSetupFailed("unknown")
            DispatchQueue.main.async {
              UIApplication.shared.isIdleTimerDisabled = false
              completion(.failure(err))
            }
            return
          }
          finalizeSuccess()
        }
      }
    } else {
      assetWriter = nil
      videoInput = nil
      finalizeSuccess()
    }
  }

  private func writeCalibrationJson() {
    let w = videoWidth > 0 ? videoWidth : 1920
    let h = videoHeight > 0 ? videoHeight : 1080
    let fx = Double(w) * 0.72
    let fy = fx
    let cx = Double(w) / 2.0
    let cy = Double(h) / 2.0

    let camera: [String: Any] = [
      "model": "pinhole",
      "focalLengthX": fx,
      "focalLengthY": fy,
      "principalPointX": cx,
      "principalPointY": cy,
      "imageWidth": w,
      "imageHeight": h,
      "imuToCamera": [
        [1, 0, 0, 0],
        [0, 1, 0, 0],
        [0, 0, 1, 0],
        [0, 0, 0, 1],
      ],
    ]
    let root: [String: Any] = ["cameras": [camera]]
    writeJsonFile(name: "calibration.json", object: root)
  }

  private func writeMetadataJson() {
    let model = SlamRecordingSession.machineModelName()
    var root: [String: Any] = [
      "device_model": model,
      "platform": "ios",
      /// `imuTemperature`：Core Motion 无公开 API；不写入伪造数据（P1）。
      "imu_temperature_status": "unavailable_no_public_api_ios",
    ]
    root["p1"] = [
      "jsonl_sorted_by_time": true,
      "focus_exposure_locked_after_delay_s": 0.2,
    ] as [String: Any]
    writeJsonFile(name: "metadata.json", object: root)
  }

  private func writeJsonFile(name: String, object: [String: Any]) {
    let url = outputDirectory.appendingPathComponent(name)
    guard JSONSerialization.isValidJSONObject(object),
          let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    else {
      return
    }
    try? data.write(to: url, options: [.atomic])
  }

  private static func machineModelName() -> String {
    var size = 0
    sysctlbyname("hw.machine", nil, &size, nil, 0)
    guard size > 0 else {
      return UIDevice.current.model
    }
    var buf = [CChar](repeating: 0, count: size)
    let err = sysctlbyname("hw.machine", &buf, &size, nil, 0)
    guard err == 0 else {
      return UIDevice.current.model
    }
    return String(cString: buf)
  }
}
