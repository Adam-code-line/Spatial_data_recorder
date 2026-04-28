import 'package:flutter/services.dart';

import '../constants/recorder_channel.dart';
import 'recorder_platform.dart';

class RecorderMethodChannel implements RecorderPlatform {
  RecorderMethodChannel()
    : _channel = const MethodChannel(RecorderChannel.name);

  final MethodChannel _channel;

  @override
  Future<void> preparePreview() async {
    await _channel.invokeMethod<void>('preparePreview');
  }

  @override
  Future<Map<String, dynamic>> getRecordingStatus() async {
    final Object? result = await _channel.invokeMethod<Object?>(
      'getRecordingStatus',
    );
    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }
    return <String, dynamic>{};
  }

  @override
  Future<void> startRecording({
    required String outputDir,
    required bool enableAudio,
  }) async {
    await _channel.invokeMethod<void>('startRecording', <String, dynamic>{
      'outputDir': outputDir,
      'enableAudio': enableAudio,
    });
  }

  @override
  Future<String> stopRecording() async {
    final Object? path = await _channel.invokeMethod<Object?>('stopRecording');
    if (path is String) {
      return path;
    }
    throw StateError('stopRecording did not return a path');
  }

  @override
  Future<void> shareFile(String filePath) async {
    await _channel.invokeMethod<void>('shareFile', <String, dynamic>{
      'filePath': filePath,
    });
  }
}
