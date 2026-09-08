import 'dart:typed_data';

import 'package:archive/archive.dart';

/// ui.pkg 打包格式 (WORK_V2 §15.2)：tar + gzip。
///
/// 目录结构：
/// ```text
/// ui.pkg
/// ├── manifest.json
/// ├── index.html
/// ├── app.js
/// ├── style.css
/// └── assets/
/// ```
///
/// 固定文件 mtime (0)：保证同内容字节确定性 (可复现构建，
/// 固件侧据此计算 package.sha256, §15.5)。
class UiPackage {
  UiPackage._();

  /// 打包 [files] (相对路径 → 内容) 为 ui.pkg 字节。
  static Uint8List pack(Map<String, Uint8List> files) {
    final archive = Archive();
    for (final entry in files.entries) {
      final file = ArchiveFile(entry.key, entry.value.length, entry.value)
        ..lastModTime = 0;
      archive.addFile(file);
    }
    final tar = TarEncoder().encodeBytes(archive);
    return Uint8List.fromList(GZipEncoder().encode(tar));
  }

  /// 解包 ui.pkg 字节 → 相对路径 → 内容 (目录项跳过)。
  static Map<String, Uint8List> unpack(Uint8List pkgBytes) {
    final tar = GZipDecoder().decodeBytes(pkgBytes);
    final archive = TarDecoder().decodeBytes(tar);
    final files = <String, Uint8List>{};
    for (final file in archive) {
      if (!file.isFile || file.name.endsWith('/')) {
        continue;
      }
      files[file.name] = Uint8List.fromList(file.content);
    }
    return files;
  }
}
