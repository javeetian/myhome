import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// UI Package 缓存：将 ui.html.gz 解压到本地缓存目录，供 UI Server 静态服务。
///
/// 当前约定 (Phase 1)：压缩包解压后即 index.html。
/// TODO: Phase 5 支持 tar.gz 多文件打包、ui_version 命中检查、SHA256 校验。
class UiCache {
  UiCache._(this.rootDir);

  /// 解压后的静态文件根目录。
  final String rootDir;

  /// index.html 绝对路径。
  String get indexPath => p.join(rootDir, 'index.html');

  /// 解压 [gzBytes] 到应用私有目录 `ui/<deviceId>/`。
  static Future<UiCache> extract(String deviceId, Uint8List gzBytes) async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'ui', deviceId));
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
    dir.createSync(recursive: true);

    final html = GZipDecoder().decodeBytes(gzBytes);
    File(p.join(dir.path, 'index.html')).writeAsBytesSync(html);
    return UiCache._(dir.path);
  }
}
