import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class RecorderLivePreview extends StatelessWidget {
  const RecorderLivePreview({super.key});

  static const _viewType =
      'com.binwu.reconstruction.spatial_data_recorder/preview';

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return const SizedBox.shrink();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: const ColoredBox(
        color: Colors.black,
        child: UiKitView(
          viewType: _viewType,
          layoutDirection: TextDirection.ltr,
        ),
      ),
    );
  }
}
