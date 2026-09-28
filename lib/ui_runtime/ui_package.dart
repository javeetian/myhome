import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'ui_image_optimizer.dart';

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

/// [UiPackageSource.collect] 结果：打包文件 + 被忽略清单排除的相对路径。
class UiPackageFiles {
  const UiPackageFiles(
    this.files,
    this.skipped, {
    this.compressedCount = 0,
    this.savedBytes = 0,
  });

  /// 相对路径 (posix 分隔) → 内容。
  final Map<String, Uint8List> files;

  /// 被 `.uipkgignore` 排除的文件 (已排序，供日志/断言)。
  final List<String> skipped;

  /// 被 [UiImageOptimizer] 压缩的图片数量 (0 = 未开启或没收益)。
  final int compressedCount;

  /// 压缩共省下的字节数。
  final int savedBytes;
}

/// UI 源目录 → 打包文件集：递归收集 + `.uipkgignore` 排除。
///
/// 源目录里常混着只对开发有用的东西——PC 预览脚本 (`serve.py`)、
/// PWA 装桌面的超大图标、设计说明等；它们进了 ui.pkg 就是白白占固件
/// flash + BLE 下载时间 (设备端 WebView 永远不请求)。排除清单让这些
/// 文件留在源目录 (serve.py 扫码预览照常)，但不进包。
///
/// `.uipkgignore` 放 UI 源目录根，一行一个模式 (`#` 注释、空行忽略)：
/// - 含 `/` 的模式匹配整条相对路径 (如 `icons/icon-1024.png`)；
/// - 不含 `/` 的模式匹配任意层级的文件名 (如 `*.txt`、`sw.js`)；
/// - 结尾 `/` 表示整个目录 (如 `icons/pwa/`)；
/// - `*` 匹配任意字符 (不跨 `/`)，`?` 匹配单个字符；
/// - 反斜杠按 `/` 处理 (Windows 手写路径也能用)。
///
/// 清单文件本身永不进包。
class UiPackageSource {
  UiPackageSource._();

  /// 排除清单文件名。
  static const String ignoreFileName = '.uipkgignore';

  /// 递归收集 [dir] 下所有文件 (相对路径、posix 分隔)，按清单过滤。
  /// [compressImages] = true 时对 PNG 做调色板量化 (见 [UiImageOptimizer])，
  /// 只改打包结果，源文件不动。
  static UiPackageFiles collect(Directory dir, {bool compressImages = false}) {
    final patterns = parseIgnore(_readIgnore(dir));
    final files = <String, Uint8List>{};
    final skipped = <String>[];
    var compressed = 0;
    var saved = 0;
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File) {
        continue;
      }
      final rel = p.relative(entity.path, from: dir.path).replaceAll('\\', '/');
      if (rel == ignoreFileName || isIgnored(rel, patterns)) {
        skipped.add(rel);
        continue;
      }
      final bytes = Uint8List.fromList(entity.readAsBytesSync());
      if (compressImages && UiImageOptimizer.supports(rel)) {
        final optimized = UiImageOptimizer.optimize(bytes);
        if (optimized != null) {
          compressed++;
          saved += bytes.length - optimized.length;
          files[rel] = optimized;
          continue;
        }
      }
      files[rel] = bytes;
    }
    skipped.sort();
    return UiPackageFiles(
      files,
      skipped,
      compressedCount: compressed,
      savedBytes: saved,
    );
  }

  /// 解析清单文本 → 模式列表。
  static List<String> parseIgnore(String content) {
    final patterns = <String>[];
    for (var line in const LineSplitter().convert(content)) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('#')) {
        continue;
      }
      patterns.add(line.replaceAll('\\', '/'));
    }
    return patterns;
  }

  /// [relPath] (posix 相对路径) 是否被 [patterns] 排除。
  static bool isIgnored(String relPath, List<String> patterns) {
    for (final pattern in patterns) {
      final re = _toRegExp(pattern);
      if (re != null && re.hasMatch(relPath)) {
        return true;
      }
    }
    return false;
  }

  /// 读取清单文件；不存在或读失败 → 空清单 (照常全量打包)。
  /// `allowMalformed`：清单里若有中文注释，GBK 编辑器存盘也不会炸。
  static String _readIgnore(Directory dir) {
    final file = File(p.join(dir.path, ignoreFileName));
    if (!file.existsSync()) {
      return '';
    }
    try {
      return utf8.decode(file.readAsBytesSync(), allowMalformed: true);
    } catch (_) {
      return '';
    }
  }

  /// 模式 → 正则 (见类注释的语法说明)；空模式返回 null。
  static RegExp? _toRegExp(String pattern) {
    final dirOnly = pattern.endsWith('/');
    final body = dirOnly ? pattern.substring(0, pattern.length - 1) : pattern;
    if (body.isEmpty) {
      return null;
    }
    final glob = StringBuffer();
    for (final rune in body.runes) {
      final ch = String.fromCharCode(rune);
      switch (ch) {
        case '*':
          glob.write('[^/]*');
        case '?':
          glob.write('[^/]');
        default:
          glob.write(RegExp.escape(ch));
      }
    }
    if (dirOnly) {
      // 目录：任意层级下该目录内的文件
      return RegExp('^(.*/)?$glob/.+');
    }
    if (body.contains('/')) {
      return RegExp('^$glob\$');
    }
    // 纯文件名：匹配任意层级的同名文件
    return RegExp('^(.*/)?$glob\$');
  }
}
