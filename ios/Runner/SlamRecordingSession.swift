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

/// P0：单目视频 + IMU JSONL + 会话结束写入 calibration / metadata（占位内参）。
final class SlamRecordingSession: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
  let outputDirectory: URL

  private let syncQueue = DispatchQueue(label: "com.binwu.reconstruction.spatial_data_recorder.recording")
  private let videoQueue = DispatchQueue(label: "com.binwu.reconstruction.spatial_data_recorder.video")
  private let motionQueue = OperationQueue()

  private var captureSession: AVCaptureSession?
  private var videoOutput: AVCaptureVideoDataOutput?
  private var assetWriter: AVAssetWriter?
  private var videoInput: AVAssetWriterInput?
  private var jsonlHandle: FileHandle?

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

    captureSession = session
    videoOutput = output

    session.startRunning()

    DispatchQueue.main.async {
      UIApplication.shared.isIdleTimerDisabled = true
      completion(nil)
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
      openJsonlIfNeeded()
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

  private func openJsonlIfNeeded() {
    guard jsonlHandle == nil else { return }
    let url = outputDirectory.appendingPathComponent("data.jsonl")
    FileManager.default.createFile(atPath: url.path, contents: nil)
    do {
      jsonlHandle = try FileHandle(forWritingTo: url)
    } catch {
      jsonlHandle = nil
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

    writeJsonLine([
      "time": t,
      "sensor": [
        "type": "gyroscope",
        "values": [gx, gy, gz],
      ],
    ])
    writeJsonLine([
      "time": t,
      "sensor": [
        "type": "accelerometer",
        "values": [ax, ay, az],
      ],
    ])
  }

  private func appendFrameJsonl(number: Int, sampleBuffer: CMSampleBuffer) {
    guard let first = firstVideoPts else { return }
    let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    let rel = CMTimeSubtract(pts, first)
    let t = CMTimeGetSeconds(rel)

    writeJsonLine([
      "number": number,
      "time": t,
      "frames": [
        ["cameraInd": 0] as [String: Any],
      ],
    ])
  }

  private func writeJsonLine(_ object: [String: Any]) {
    guard let h = jsonlHandle else { return }
    guard JSONSerialization.isValidJSONObject(object),
          let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
          let line = String(data: data, encoding: .utf8)
    else {
      return
    }
    if let nl = (line + "\n").data(using: .utf8) {
      h.write(nl)
    }
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

    let finalizeSuccess: () -> Void = { [weak self] in
      guard let self = self else { return }
      self.jsonlHandle?.closeFile()
      self.jsonlHandle = nil
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
            self.jsonlHandle?.closeFile()
            self.jsonlHandle = nil
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
      jsonlHandle?.closeFile()
      jsonlHandle = nil
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
    let root: [String: Any] = [
      "device_model": model,
      "platform": "ios",
    ]
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
