/// 录制能力抽象，便于测试与后续替换为假实现。
abstract class RecorderPlatform {
  Future<void> preparePreview();

  Future<Map<String, dynamic>> getRecordingStatus();

  /// [outputDir] 为本次会话目录的绝对路径（需已创建）。
  Future<void> startRecording({required String outputDir});

  /// 结束录制并返回会话目录路径（与 [startRecording] 传入的目录一致）。
  Future<String> stopRecording();
}
