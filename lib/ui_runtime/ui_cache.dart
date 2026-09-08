import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'ui_package.dart';

/// UI Package 缓存 (WORK_V2 §15.4/§27)。
///
/// 目录布局：`ui/<deviceId>/<uiVersion>/` → 解包后的 UI 文件。
/// 缓存键 = Device ID + UI Version (§15.4)。
class UiCache {
  UiCache(this.rootDir);

  /// 缓存根目录 (应用私有 ui/ 目录)。
  final String rootDir;

  static Future<UiCache> open() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'ui'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return UiCache(dir.path);
  }

  /// 版本目录路径。
  String versionDir(String deviceId, String uiVersion) =>
      p.join(rootDir, deviceId, uiVersion);

  /// 缓存命中检查 (§15.3)：版本目录存在且含 index.html。
  /// 命中返回静态根目录，否则 null。
  String? lookup(String deviceId, String uiVersion) {
    final dir = Directory(versionDir(deviceId, uiVersion));
    if (!File(p.join(dir.path, 'index.html')).existsSync()) {
      return null;
    }
    return dir.path;
  }

  /// 校验并解包 ui.pkg → 写入版本目录 (§15.5)。
  /// 完整性校验失败抛异常，不污染缓存。
  Future<String> store(
    String deviceId,
    String uiVersion,
    Uint8List pkgBytes, {
    int? expectedSize,
    String? expectedSha256,
  }) async {
    if (expectedSize != null && pkgBytes.length != expectedSize) {
      throw StateError('UI 包大小不符: 期望 $expectedSize, 实际 ${pkgBytes.length}');
    }
    if (expectedSha256 != null) {
      final actual = sha256.convert(pkgBytes).toString();
      if (actual != expectedSha256) {
        throw StateError('UI 包 SHA256 校验失败');
      }
    }
    // 校验全部通过后才写盘
    final files = UiPackage.unpack(pkgBytes);
    if (!files.containsKey('index.html')) {
      throw StateError('UI 包缺少 index.html');
    }
    final target = Directory(versionDir(deviceId, uiVersion));
    if (target.existsSync()) {
      target.deleteSync(recursive: true);
    }
    target.createSync(recursive: true);
    for (final entry in files.entries) {
      final file = File(p.normalize(p.join(target.path, entry.key)));
      if (!file.path.startsWith(target.path + p.separator)) {
        throw StateError('UI 包含非法路径: ${entry.key}'); // 防目录穿越
      }
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(entry.value);
    }
    return target.path;
  }
}
