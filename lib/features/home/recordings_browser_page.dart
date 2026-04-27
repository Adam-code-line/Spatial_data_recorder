import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:spatial_data_recorder/core/upload/models/upload_enqueue_result.dart';
import 'package:spatial_data_recorder/core/upload/models/upload_queue_state.dart';
import 'package:spatial_data_recorder/core/upload/models/upload_session_context.dart';
import 'package:spatial_data_recorder/core/upload/models/upload_task.dart';
import 'package:spatial_data_recorder/core/upload/upload_providers.dart';
import 'package:spatial_data_recorder/features/home/upload_session_context_dialog.dart';

class RecordingsBrowserPage extends ConsumerStatefulWidget {
  const RecordingsBrowserPage({super.key});

  @override
  ConsumerState<RecordingsBrowserPage> createState() =>
      _RecordingsBrowserPageState();
}

class _RecordingsBrowserPageState extends ConsumerState<RecordingsBrowserPage> {
  Directory? _outputRoot;
  Directory? _currentDir;
  List<FileSystemEntity> _entries = const [];
  List<_SceneGroup> _sceneGroups = const [];
  String? _activeSceneName;
  String? _activeSeqName;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRoot();
  }

  Future<void> _loadRoot() async {
    final docs = await getApplicationDocumentsDirectory();
    final outputDir = Directory(p.join(docs.path, 'output'));
    if (!await outputDir.exists()) {
      await outputDir.create(recursive: true);
    }
    await _reloadGroupedRoot(outputDir);
  }

  Future<void> _reloadGroupedRoot([Directory? dir]) async {
    final outputRoot = dir ?? _outputRoot;
    if (outputRoot == null) {
      return;
    }
    setState(() {
      _loading = true;
    });
    final sceneGroups = await _buildSceneGroups(outputRoot);
    if (!mounted) return;
    setState(() {
      _outputRoot = outputRoot;
      _currentDir = null;
      _sceneGroups = sceneGroups;
      _entries = const [];
      _activeSceneName = null;
      _activeSeqName = null;
      _loading = false;
    });
  }

  Future<List<_SceneGroup>> _buildSceneGroups(Directory outputRoot) async {
    final contextService = ref.read(uploadSessionContextServiceProvider);
    final directories =
        outputRoot
            .listSync(followLinks: false)
            .whereType<Directory>()
            .where(
              (directory) =>
                  p.basename(directory.path).startsWith('recording_'),
            )
            .toList()
          ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));

    final buckets = <String, Map<String, List<_SessionEntry>>>{};
    for (final directory in directories) {
      final context = await contextService.readForSession(directory.path);
      final sceneName = context?.sceneName ?? '未设置Scene';
      final seqName = context?.seqName ?? '未设置Seq';
      final sceneBucket = buckets.putIfAbsent(
        sceneName,
        () => <String, List<_SessionEntry>>{},
      );
      final seqBucket = sceneBucket.putIfAbsent(
        seqName,
        () => <_SessionEntry>[],
      );
      seqBucket.add(_SessionEntry(directory: directory, context: context));
    }

    final sceneNames = buckets.keys.toList()..sort();
    return sceneNames
        .map((sceneName) {
          final seqBuckets = buckets[sceneName]!;
          final seqNames = seqBuckets.keys.toList()..sort();
          final seqGroups = seqNames
              .map((seqName) {
                final sessions = seqBuckets[seqName]!
                  ..sort(
                    (a, b) => p
                        .basename(a.directory.path)
                        .compareTo(p.basename(b.directory.path)),
                  );
                return _SeqGroup(seqName: seqName, sessions: sessions);
              })
              .toList(growable: false);
          return _SceneGroup(sceneName: sceneName, seqGroups: seqGroups);
        })
        .toList(growable: false);
  }

  Future<void> _openDirectory(Directory dir) async {
    setState(() {
      _loading = true;
    });

    final entries = dir.listSync(followLinks: false);
    entries.sort((a, b) {
      final aIsDir = a is Directory;
      final bIsDir = b is Directory;
      if (aIsDir != bIsDir) {
        return aIsDir ? -1 : 1;
      }
      return p.basename(a.path).compareTo(p.basename(b.path));
    });

    if (!mounted) return;
    setState(() {
      _currentDir = dir;
      _entries = entries;
      _outputRoot ??= Directory(p.join(dir.parent.path));
      _loading = false;
    });
  }

  Future<void> _handleTap(FileSystemEntity entity) async {
    if (entity is Directory) {
      await _openDirectory(entity);
      return;
    }
    if (entity is File) {
      final stat = await entity.stat();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${p.basename(entity.path)} (${stat.size} bytes)'),
        ),
      );
    }
  }

  Future<void> _handleRecordingUpload(
    Directory directory,
    UploadTask? existingTask,
  ) async {
    try {
      final contextService = ref.read(uploadSessionContextServiceProvider);
      await contextService.ensureContextForSession(directory.path);
      final uploadContext = await showUploadSessionContextDialog(
        context: context,
        sessionPath: directory.path,
        contextService: contextService,
      );
      if (uploadContext == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已保留本地上传信息，未加入上传队列。')));
        return;
      }
      await contextService.writeForSession(directory.path, uploadContext);

      if (existingTask != null &&
          (existingTask.status == UploadTaskStatus.failed ||
              existingTask.status == UploadTaskStatus.cancelled)) {
        await ref
            .read(uploadQueueControllerProvider.notifier)
            .retrySession(directory.path);
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已重新加入上传队列。')));
        return;
      }

      final result = await ref
          .read(uploadQueueControllerProvider.notifier)
          .enqueueSession(directory.path);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_enqueueMessage(result))));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('加入上传队列失败：$e')));
    } finally {
      await _reloadGroupedDataIfNeeded();
    }
  }

  Future<void> _reloadGroupedDataIfNeeded() async {
    final outputRoot = _outputRoot;
    if (outputRoot == null) {
      return;
    }
    final sceneGroups = await _buildSceneGroups(outputRoot);
    if (!mounted) return;
    setState(() {
      _sceneGroups = sceneGroups;
    });
  }

  String _enqueueMessage(UploadEnqueueResult result) {
    switch (result) {
      case UploadEnqueueResult.created:
        return '已加入上传队列。';
      case UploadEnqueueResult.requeued:
        return '已重新加入上传队列。';
      case UploadEnqueueResult.alreadyQueued:
        return '该会话已在上传队列中。';
      case UploadEnqueueResult.alreadySuccess:
        return '该会话已上传成功。';
    }
  }

  UploadTask? _findTaskForSession(List<UploadTask> tasks, String sessionPath) {
    final normalizedPath = p.normalize(sessionPath);
    for (final task in tasks.reversed) {
      if (p.normalize(task.sessionPath) == normalizedPath) {
        return task;
      }
    }
    return null;
  }

  IconData _statusIcon(UploadTaskStatus status) {
    switch (status) {
      case UploadTaskStatus.waiting:
      case UploadTaskStatus.compressing:
      case UploadTaskStatus.retrying:
        return Icons.schedule;
      case UploadTaskStatus.uploading:
        return Icons.cloud_upload;
      case UploadTaskStatus.success:
        return Icons.check_circle;
      case UploadTaskStatus.failed:
        return Icons.error;
      case UploadTaskStatus.cancelled:
        return Icons.cancel;
    }
  }

  String _uploadActionLabel(UploadTask? task) {
    if (task == null) {
      return '上传';
    }
    if (task.status == UploadTaskStatus.failed ||
        task.status == UploadTaskStatus.cancelled) {
      return '重试上传';
    }
    if (task.status == UploadTaskStatus.success) {
      return '已上传';
    }
    return '上传中';
  }

  bool _canTriggerUpload(UploadTask? task) {
    if (task == null) {
      return true;
    }
    return task.status == UploadTaskStatus.failed ||
        task.status == UploadTaskStatus.cancelled;
  }

  _SceneGroup? get _selectedSceneGroup {
    final sceneName = _activeSceneName;
    if (sceneName == null) {
      return null;
    }
    for (final group in _sceneGroups) {
      if (group.sceneName == sceneName) {
        return group;
      }
    }
    return null;
  }

  _SeqGroup? get _selectedSeqGroup {
    final sceneGroup = _selectedSceneGroup;
    final seqName = _activeSeqName;
    if (sceneGroup == null || seqName == null) {
      return null;
    }
    for (final group in sceneGroup.seqGroups) {
      if (group.seqName == seqName) {
        return group;
      }
    }
    return null;
  }

  Future<void> _handleBack() async {
    final current = _currentDir;
    final outputRoot = _outputRoot;
    if (current != null) {
      if (outputRoot != null &&
          p.normalize(current.parent.path) == p.normalize(outputRoot.path)) {
        if (!mounted) return;
        setState(() {
          _currentDir = null;
          _entries = const [];
        });
        return;
      }
      await _openDirectory(current.parent);
      return;
    }
    if (_activeSeqName != null) {
      setState(() {
        _activeSeqName = null;
      });
      return;
    }
    if (_activeSceneName != null) {
      setState(() {
        _activeSceneName = null;
      });
      return;
    }
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  String _pageTitle() {
    if (_currentDir != null) {
      return p.basename(_currentDir!.path);
    }
    if (_activeSeqName != null) {
      return _activeSeqName!;
    }
    if (_activeSceneName != null) {
      return _activeSceneName!;
    }
    return '录制文件';
  }

  @override
  Widget build(BuildContext context) {
    final uploadState = ref.watch(uploadQueueControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_pageTitle()),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _handleBack,
        ),
      ),
      body: _buildBody(uploadState),
    );
  }

  Widget _buildBody(UploadQueueState uploadState) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_currentDir != null) {
      return _buildDirectoryList(uploadState);
    }
    if (_activeSeqName != null) {
      return _buildSessionGroupList(uploadState);
    }
    if (_activeSceneName != null) {
      return _buildSeqGroupList();
    }
    return _buildSceneGroupList();
  }

  Widget _buildSceneGroupList() {
    if (_sceneGroups.isEmpty) {
      return const Center(child: Text('暂无录制文件。'));
    }
    return ListView.separated(
      itemCount: _sceneGroups.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final group = _sceneGroups[index];
        return ListTile(
          leading: const Icon(Icons.folder_copy),
          title: Text(group.sceneName),
          subtitle: Text(
            '${group.seqGroups.length} 个 seq，${group.sessionCount} 个录制',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            setState(() {
              _activeSceneName = group.sceneName;
            });
          },
        );
      },
    );
  }

  Widget _buildSeqGroupList() {
    final sceneGroup = _selectedSceneGroup;
    if (sceneGroup == null) {
      return const Center(child: Text('未找到对应场景分组。'));
    }
    return ListView.separated(
      itemCount: sceneGroup.seqGroups.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final group = sceneGroup.seqGroups[index];
        return ListTile(
          leading: const Icon(Icons.folder_shared),
          title: Text(group.seqName),
          subtitle: Text('${group.sessions.length} 个录制'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            setState(() {
              _activeSeqName = group.seqName;
            });
          },
        );
      },
    );
  }

  Widget _buildSessionGroupList(UploadQueueState uploadState) {
    final seqGroup = _selectedSeqGroup;
    if (seqGroup == null) {
      return const Center(child: Text('未找到对应 seq 分组。'));
    }
    return ListView.separated(
      itemCount: seqGroup.sessions.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final session = seqGroup.sessions[index];
        final task = _findTaskForSession(
          uploadState.tasks,
          session.directory.path,
        );
        return _buildRecordingDirectoryTile(session.directory, task);
      },
    );
  }

  Widget _buildDirectoryList(UploadQueueState uploadState) {
    return ListView.separated(
      itemCount: _entries.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final entry = _entries[index];
        final directory = entry is Directory ? entry : null;
        final isDir = directory != null;
        final name = p.basename(entry.path);
        final isRecordingDir = isDir && name.startsWith('recording_');
        final uploadTask = isRecordingDir
            ? _findTaskForSession(uploadState.tasks, entry.path)
            : null;
        if (isRecordingDir) {
          return _buildRecordingDirectoryTile(directory, uploadTask);
        }
        return ListTile(
          leading: Icon(isDir ? Icons.folder : Icons.insert_drive_file),
          title: Text(name),
          trailing: Icon(isDir ? Icons.chevron_right : Icons.more_horiz),
          onTap: () => _handleTap(entry),
        );
      },
    );
  }

  Widget _buildRecordingDirectoryTile(
    Directory directory,
    UploadTask? uploadTask,
  ) {
    final name = p.basename(directory.path);
    return ListTile(
      leading: const Icon(Icons.folder),
      title: Text(name),
      subtitle: uploadTask == null
          ? null
          : Text(
              _uploadActionLabel(uploadTask),
              style: TextStyle(
                color: uploadTask.status == UploadTaskStatus.failed
                    ? Colors.red
                    : null,
              ),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (uploadTask != null)
            Icon(
              _statusIcon(uploadTask.status),
              size: 18,
              color: uploadTask.status == UploadTaskStatus.failed
                  ? Colors.red
                  : null,
            ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'upload') {
                _handleRecordingUpload(directory, uploadTask);
              } else if (value == 'open') {
                _openDirectory(directory);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem<String>(value: 'open', child: Text('打开目录')),
              PopupMenuItem<String>(
                value: 'upload',
                enabled: _canTriggerUpload(uploadTask),
                child: Text(_uploadActionLabel(uploadTask)),
              ),
            ],
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: () => _openDirectory(directory),
      onLongPress: () => _handleRecordingUpload(directory, uploadTask),
    );
  }
}

class _SceneGroup {
  const _SceneGroup({required this.sceneName, required this.seqGroups});

  final String sceneName;
  final List<_SeqGroup> seqGroups;

  int get sessionCount =>
      seqGroups.fold<int>(0, (count, group) => count + group.sessions.length);
}

class _SeqGroup {
  const _SeqGroup({required this.seqName, required this.sessions});

  final String seqName;
  final List<_SessionEntry> sessions;
}

class _SessionEntry {
  const _SessionEntry({required this.directory, required this.context});

  final Directory directory;
  final UploadSessionContext? context;
}
