import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// 在应用文档目录下创建 `recordings/<uuid>/` 作为一次采集会话目录。
Future<Directory> createSessionDirectory() async {
  final root = await getApplicationDocumentsDirectory();
  final id = const Uuid().v4();
  final dir = Directory(p.join(root.path, 'recordings', id));
  await dir.create(recursive: true);
  return dir;
}
