import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/upload/models/upload_session_context.dart';
import '../../core/upload/services/upload_session_context_service.dart';

Future<UploadSessionContext?> showUploadSessionContextDialog({
  required BuildContext context,
  required String sessionPath,
  required UploadSessionContextService contextService,
}) async {
  final existing = await contextService.readForSession(sessionPath);
  final defaults = await contextService.readDefaults(sessionPath);
  final audioTrackPresent = await contextService.readAudioTrackPresent(
    sessionPath,
  );
  if (!context.mounted) {
    return null;
  }

  return showDialog<UploadSessionContext>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return _UploadSessionContextDialog(
        sessionName: p.basename(sessionPath),
        existing: existing,
        defaults: defaults,
        audioTrackPresent: audioTrackPresent,
        contextService: contextService,
      );
    },
  );
}

class _UploadSessionContextDialog extends StatefulWidget {
  const _UploadSessionContextDialog({
    required this.sessionName,
    required this.existing,
    required this.defaults,
    required this.audioTrackPresent,
    required this.contextService,
  });

  final String sessionName;
  final UploadSessionContext? existing;
  final UploadSessionContext? defaults;
  final bool audioTrackPresent;
  final UploadSessionContextService contextService;

  @override
  State<_UploadSessionContextDialog> createState() =>
      _UploadSessionContextDialogState();
}

class _UploadSessionContextDialogState
    extends State<_UploadSessionContextDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _sceneController;
  late final TextEditingController _seqController;
  late final TextEditingController _groupController;

  late UploadCaptureType _captureType;
  late bool _reuseRecentScene;
  late bool _reuseRecentSeq;
  late bool _groupEnabled;
  late bool _reuseRecentGroup;

  UploadSessionContext? get _defaults => widget.defaults;
  bool get _hasRecentScene =>
      _defaults != null && _defaults!.sceneName.isNotEmpty;
  bool get _hasRecentSeq => _defaults != null && _defaults!.seqName.isNotEmpty;
  bool get _hasRecentGroup =>
      _defaults != null &&
      _defaults!.pairGroupId != null &&
      _defaults!.pairGroupId!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    final seed = widget.existing ?? widget.defaults;
    _captureType = seed?.captureType ?? UploadCaptureType.sceneOnly;
    _sceneController = TextEditingController(
      text: widget.existing?.sceneName ?? '',
    );
    _seqController = TextEditingController(
      text: widget.existing?.seqName ?? '',
    );
    _groupController = TextEditingController(
      text: widget.existing?.pairGroupId ?? '',
    );
    _reuseRecentScene = false;
    _reuseRecentSeq = false;
    _groupEnabled = widget.existing?.isGrouped ?? false;
    _reuseRecentGroup = false;
  }

  @override
  void dispose() {
    _sceneController.dispose();
    _seqController.dispose();
    _groupController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('上传设置'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.sessionName,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<UploadCaptureType>(
                  value: _captureType,
                  decoration: const InputDecoration(
                    labelText: '场景类型',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: UploadCaptureType.sceneOnly,
                      child: Text('纯场景'),
                    ),
                    DropdownMenuItem(
                      value: UploadCaptureType.humanInScene,
                      child: Text('带人'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _captureType = value;
                    });
                  },
                ),
                const SizedBox(height: 12),
                if (_hasRecentScene)
                  SwitchListTile(
                    value: _reuseRecentScene,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('沿用最近 Scene'),
                    subtitle: Text(_defaults!.sceneName),
                    onChanged: (value) {
                      setState(() {
                        _reuseRecentScene = value;
                      });
                    },
                  ),
                TextFormField(
                  controller: _sceneController,
                  enabled: !_reuseRecentScene,
                  decoration: InputDecoration(
                    labelText: 'Scene 名称',
                    hintText: widget.contextService.generateSceneName(
                      widget.sessionName,
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (_reuseRecentScene) {
                      return null;
                    }
                    final trimmed = value?.trim() ?? '';
                    if (trimmed.isEmpty) {
                      return null;
                    }
                    if (!widget.contextService.isValidSegment(trimmed)) {
                      return '仅支持字母、数字、点、下划线、短横线';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                if (_hasRecentSeq)
                  SwitchListTile(
                    value: _reuseRecentSeq,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('沿用最近 Seq'),
                    subtitle: Text(_defaults!.seqName),
                    onChanged: (value) {
                      setState(() {
                        _reuseRecentSeq = value;
                      });
                    },
                  ),
                TextFormField(
                  controller: _seqController,
                  enabled: !_reuseRecentSeq,
                  decoration: InputDecoration(
                    labelText: 'Seq 名称',
                    hintText: widget.contextService.generateSeqName(
                      widget.sessionName,
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (_reuseRecentSeq) {
                      return null;
                    }
                    final trimmed = value?.trim() ?? '';
                    if (trimmed.isEmpty) {
                      return null;
                    }
                    if (!widget.contextService.isValidSegment(trimmed)) {
                      return '仅支持字母、数字、点、下划线、短横线';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  value: _groupEnabled,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('标记为同组拍摄'),
                  subtitle: const Text('同组视频会共享同一个 groupId'),
                  onChanged: (value) {
                    setState(() {
                      _groupEnabled = value;
                      if (!value) {
                        _reuseRecentGroup = false;
                      }
                    });
                  },
                ),
                if (_groupEnabled && _hasRecentGroup)
                  SwitchListTile(
                    value: _reuseRecentGroup,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('沿用最近 Group'),
                    subtitle: Text(_defaults!.pairGroupId!),
                    onChanged: (value) {
                      setState(() {
                        _reuseRecentGroup = value;
                      });
                    },
                  ),
                if (_groupEnabled)
                  TextFormField(
                    controller: _groupController,
                    enabled: !_reuseRecentGroup,
                    decoration: InputDecoration(
                      labelText: 'Group ID',
                      hintText: widget.contextService.generatePairGroupId(
                        widget.sessionName,
                      ),
                      border: const OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (!_groupEnabled || _reuseRecentGroup) {
                        return null;
                      }
                      final trimmed = value?.trim() ?? '';
                      if (trimmed.isEmpty) {
                        return null;
                      }
                      if (!widget.contextService.isValidSegment(trimmed)) {
                        return '仅支持字母、数字、点、下划线、短横线';
                      }
                      return null;
                    },
                  ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('音频状态'),
                  subtitle: Text(
                    widget.audioTrackPresent ? '本次录制已包含音频' : '本次录制无音频，但允许继续上传',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('仅保存'),
        ),
        FilledButton(onPressed: _submit, child: const Text('确认并上传')),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final sceneName = _reuseRecentScene && _hasRecentScene
        ? _defaults!.sceneName
        : _resolveOrGenerate(
            _sceneController.text,
            widget.contextService.generateSceneName(widget.sessionName),
          );
    final seqName = _reuseRecentSeq && _hasRecentSeq
        ? _defaults!.seqName
        : _resolveOrGenerate(
            _seqController.text,
            widget.contextService.generateSeqName(widget.sessionName),
          );
    final pairGroupId = !_groupEnabled
        ? null
        : (_reuseRecentGroup && _hasRecentGroup
              ? _defaults!.pairGroupId
              : _resolveOrGenerate(
                  _groupController.text,
                  widget.contextService.generatePairGroupId(widget.sessionName),
                ));

    final sessionContext = UploadSessionContext(
      captureType: _captureType,
      sceneName: sceneName,
      seqName: seqName,
      pairGroupId: pairGroupId,
      audioTrackPresent: widget.audioTrackPresent,
      confirmedAt: DateTime.now().toUtc(),
    );
    Navigator.of(context).pop(sessionContext);
  }

  String _resolveOrGenerate(String rawValue, String generatedFallback) {
    final normalized = widget.contextService.normalizeSegment(rawValue);
    if (normalized.isNotEmpty) {
      return normalized;
    }
    return generatedFallback;
  }
}
