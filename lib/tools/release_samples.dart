import 'dart:io';

import 'package:path/path.dart' as p;

/// 发布包随附源码：把 `sdk/device`（设备端协议运行时）与示例工程拷进 Release 目录的
/// `samples/`，随 Windows 安装包装到 <安装目录>\samples\，用户自己拷进设备 SDK
/// 完成移植第一步（使用文档 §7）。
///
/// 为什么不直接放进安装包配置：inno_bundle 的 `[Files]` 段是遍历 Release 目录生成的
/// （目录 → `DestDir: {app}\<目录名>`），所以只要在打包前把 `samples/` 摆进去即可。
/// 顺序必须是：`flutter build windows` → 本工具 → `dart run inno_bundle --no-app`
/// （inno_bundle 自己会先跑 flutter build，把 Release 目录重写一遍）。
class ReleaseSamples {
  ReleaseSamples._();

  /// Release 目录下随附源码的目录名（安装后为 <安装目录>\samples\）。
  static const String dirName = 'samples';

  /// 不随发布包发出的文件后缀：开发机上的 C 编译产物（MSVC）。
  static const Set<String> excludedExtensions = <String>{
    '.obj',
    '.exe',
    '.pdb',
    '.ilk',
    '.exp',
    '.lib',
  };

  /// 该文件是否随发布包发出（编译产物、仓库占位文件不发）。
  static bool shouldShip(String relPath) {
    if (excludedExtensions.contains(p.extension(relPath).toLowerCase())) {
      return false;
    }
    return p.basename(relPath) != '.gitkeep';
  }

  /// 递归拷贝 [from] 到 [to]，跳过 [shouldShip] 认为不发的内容；返回拷贝的文件数。
  static int copyTree(Directory from, Directory to) {
    var count = 0;
    for (final entity in from.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final rel = p.relative(entity.path, from: from.path);
      if (!shouldShip(rel)) continue;
      File(p.join(to.path, rel))
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(entity.readAsBytesSync());
      count++;
    }
    return count;
  }

  /// 随附源码的说明文件（仓库里没有这份源文件，打包时生成）。
  static const String readmeText = '''
Device Studio 随附源码
======================

device_sdk\\   设备端协议运行时完整源码（移植第一步要拷给设备 SDK 的代码）
               含 core\\ 协议与运行时、hardware\\ 硬件接口、platform\\jieli\\ 平台胶水、
               examples\\ 应用示例、README.md（接入说明）、deploy_to_sdk 部署脚本。

light1\\       一个完整示例工程：device.yaml（设备定义）+ ui\\（界面源码）
               + generated\\（生成的代码）+ device_app.c / ui_assets.c（硬件实现）
               + build\\ui.pkg（打好的界面包）。可整个拷到设备 SDK 编译，
               也可以对着它写自己的设备。

两份都是普通文件夹，直接拷贝即可，详见《使用文档》§7（Studio「帮助 → 使用说明」）。
''';

  /// 写 samples/README.txt（统一 CRLF，Windows 记事本友好）。
  static void writeReadme(Directory samplesDir) {
    File(p.join(samplesDir.path, 'README.txt')).writeAsStringSync(
      readmeText.replaceAll('\n', '\r\n'),
    );
  }

  /// 把 [sources]（目录名 → 源目录）拷进 `<releaseDir>/samples/`，
  /// 先删后拷（不留上一次打包的旧文件）；返回 目录名 → 拷贝文件数。
  static Map<String, int> stage({
    required Directory releaseDir,
    required Map<String, Directory> sources,
  }) {
    final samplesDir = Directory(p.join(releaseDir.path, dirName));
    if (samplesDir.existsSync()) samplesDir.deleteSync(recursive: true);
    samplesDir.createSync(recursive: true);

    final counts = <String, int>{};
    for (final entry in sources.entries) {
      counts[entry.key] =
          copyTree(entry.value, Directory(p.join(samplesDir.path, entry.key)));
    }
    writeReadme(samplesDir);
    return counts;
  }
}
