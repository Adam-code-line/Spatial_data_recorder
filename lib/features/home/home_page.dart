import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/recording/session_directory.dart';
import '../../core/recorder/recorder_providers.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  Map<String, dynamic>? _status;
  Object? _lastError;
  String? _activeSessionPath;
  bool _busy = false;

  bool get _isIos => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  Future<bool> _ensureCameraPermission() async {
    var status = await Permission.camera.status;
    if (status.isGranted) return true;

    status = await Permission.camera.request();
    if (status.isGranted) return true;

    if (status.isPermanentlyDenied || status.isRestricted) {
      if (!mounted) return false;
      final goSettings = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('需要相机权限'),
          content: const Text(
            '当前相机权限被拒绝，请前往 iOS 设置中为 Spatial Data Recorder 打开相机权限。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('去设置'),
            ),
          ],
        ),
      );
      if (goSettings == true) {
        await openAppSettings();
      }
      return false;
    }

    _toast('需要相机权限才能录制视频。');
    return false;
  }

  Future<void> _refreshStatus() async {
    setState(() {
      _lastError = null;
    });
    try {
      final status = await ref
          .read(recorderPlatformProvider)
          .getRecordingStatus();
      if (mounted) {
        setState(() {
          _status = status;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _lastError = e;
        });
      }
    }
  }

  Future<void> _startRecording() async {
    if (!_isIos) {
      _toast('P0 采集仅在 iOS 真机上可用。');
      return;
    }
    setState(() {
      _busy = true;
      _lastError = null;
    });
    try {
      final ok = await _ensureCameraPermission();
      if (!ok) {
        return;
      }

      final dir = await createSessionDirectory();
      _activeSessionPath = dir.path;

      await ref
          .read(recorderPlatformProvider)
          .startRecording(outputDir: dir.path);
      await _refreshStatus();
      if (mounted) {
        _toast('已开始录制');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _lastError = e;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _stopRecording() async {
    if (!_isIos) {
      return;
    }
    setState(() {
      _busy = true;
      _lastError = null;
    });
    try {
      final path = await ref.read(recorderPlatformProvider).stopRecording();
      _activeSessionPath = path;
      await _refreshStatus();
      if (mounted) {
        _toast('已停止。数据目录：$path');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _lastError = e;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  void _toast(String msg) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshStatus());
  }

  @override
  Widget build(BuildContext context) {
    final recording = _status?['recording'] == true;
    final lastPath = _status?['lastCompletedSessionPath'] as String?;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Spatial Data Recorder'),
        actions: [
          IconButton(
            tooltip: '刷新状态',
            onPressed: _busy ? null : _refreshStatus,
            icon: const Icon(Icons.sync),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isIos
                  ? 'P0：生成 data.mov、data.jsonl、calibration.json、metadata.json（单目 + IMU，无麦克风）。'
                  : '当前平台为 ${_platformLabel()}；完整采集请使用 iOS 真机。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: (_busy || recording || !_isIos)
                      ? null
                      : _startRecording,
                  icon: const Icon(Icons.fiber_manual_record),
                  label: const Text('开始录制'),
                ),
                const SizedBox(width: 12),
                FilledButton.tonalIcon(
                  onPressed: (_busy || !recording || !_isIos)
                      ? null
                      : _stopRecording,
                  icon: const Icon(Icons.stop),
                  label: const Text('停止'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_busy) const LinearProgressIndicator(),
            const SizedBox(height: 8),
            if (_lastError != null)
              Text(
                '错误: $_lastError',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_status != null) Text('状态: $_status'),
            if (lastPath != null) ...[
              const SizedBox(height: 8),
              SelectableText('上次完成目录：\n$lastPath'),
            ],
            if (_activeSessionPath != null) ...[
              const SizedBox(height: 8),
              SelectableText('当前会话目录：\n$_activeSessionPath'),
            ],
          ],
        ),
      ),
    );
  }

  String _platformLabel() {
    if (kIsWeb) {
      return 'Web';
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'iOS';
      case TargetPlatform.android:
        return 'Android';
      case TargetPlatform.macOS:
        return 'macOS';
      case TargetPlatform.windows:
        return 'Windows';
      case TargetPlatform.linux:
        return 'Linux';
      case TargetPlatform.fuchsia:
        return 'Fuchsia';
    }
  }
}
