import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

bool _same(List<int> a, List<int>? b) {
  if (b == null || a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// 电脑端驱动：把手机传回的截图存到 build/screenshots/，并做 T-FIX-3 判定
Future<void> main() {
  final Map<String, List<int>> shots = <String, List<int>>{};

  return integrationDriver(
    onScreenshot: (String name, List<int> bytes,
        [Map<String, Object?>? args]) async {
      final File file = File('build/screenshots/$name.png');
      await file.create(recursive: true);
      await file.writeAsBytes(bytes);
      shots[name] = bytes;
      // 字节→字节切换后画面必须变化；修复前 iOS 不换图，截图完全相同
      if (name == 't_fix3_2_bytes_end') {
        return !_same(bytes, shots['t_fix3_1_bytes_start']);
      }
      if (name == 't_fix3_3_bytes_start') {
        return !_same(bytes, shots['t_fix3_2_bytes_end']);
      }
      // S15：点“修复资源”后损坏点换成九宫格气泡，画面必须变化
      if (name == 's15_image_repaired') {
        return !_same(bytes, shots['s15_image_broken']);
      }
      return true;
    },
  );
}
