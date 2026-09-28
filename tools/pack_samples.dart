import 'dart:io';

import 'package:myhome/tools/release_samples.dart';
import 'package:path/path.dart' as p;

/// 打包 Windows 安装包前，把随附源码（sdk/device 协议运行时 + light1 示例工程）
/// 拷进 Release 目录的 samples/，随安装包装到 <安装目录>\samples\（使用文档 §7）。
///
/// 用法：
/// ```bash
/// flutter build windows --release -t lib/studio/studio_main.dart   # 或照常先构建
/// dart run tools/pack_samples.dart                                 # 摆好 samples/
/// dart run inno_bundle --release --no-app                          # 生成安装包
/// ```
/// `--no-app` 表示不重跑 flutter build —— 它会重写 Release 目录，刚摆好的
/// samples/ 不保险。
/// 退出码：0 = PASS；1 = ERROR；2 = 用法错误。
const String _defaultReleaseDir = 'build/windows/x64/runner/Release';
const String _defaultSdkDevice = 'sdk/device';
const String _defaultLight1 = r'C:\work\jl\jl380n_demo\SDK\apps\myhome\light1';

Future<void> main(List<String> args) async {
  String releaseDir = _defaultReleaseDir;
  String sdkDevice = _defaultSdkDevice;
  String light1 =
      Platform.environment['MYHOME_LIGHT1']?.trim().isNotEmpty == true
          ? Platform.environment['MYHOME_LIGHT1']!.trim()
          : _defaultLight1;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--release-dir':
        if (++i >= args.length) exit(_usage('--release-dir 缺参数'));
        releaseDir = args[i];
      case '--sdk-device':
        if (++i >= args.length) exit(_usage('--sdk-device 缺参数'));
        sdkDevice = args[i];
      case '--light1':
        if (++i >= args.length) exit(_usage('--light1 缺参数'));
        light1 = args[i];
      case '-h':
      case '--help':
        _usage();
        exit(0);
      default:
        exit(_usage('未知参数: ${args[i]}'));
    }
  }

  final release = Directory(releaseDir);
  if (!release.existsSync()) {
    stderr.writeln('[ERROR] Release 目录不存在: ${p.absolute(releaseDir)}');
    stderr.writeln('        先构建：');
    stderr.writeln('        flutter build windows --release '
        '-t lib/studio/studio_main.dart');
    exit(1);
  }

  final sources = <String, Directory>{};
  for (final (name, dir) in <(String, String)>[
    ('device_sdk', sdkDevice),
    ('light1', light1),
  ]) {
    final d = Directory(dir);
    if (!d.existsSync()) {
      stderr.writeln('[ERROR] 随附源码目录不存在: ${p.absolute(dir)}'
          '${name == 'light1' ? '（用 --light1 <目录> 或环境变量 MYHOME_LIGHT1 指定）' : ''}');
      exit(1);
    }
    sources[name] = d;
  }

  final counts = ReleaseSamples.stage(releaseDir: release, sources: sources);
  stdout.writeln('随附源码 → ${p.join(releaseDir, ReleaseSamples.dirName)}');
  for (final entry in counts.entries) {
    stdout.writeln('  ${entry.key}/  ${entry.value} 个文件');
  }
  stdout.writeln('下一步（生成安装包，别再跑 flutter build）：');
  stdout.writeln('  dart run inno_bundle --release --no-app');
}

int _usage([String? error]) {
  if (error != null) stderr.writeln('[ERROR] $error');
  stderr.writeln('用法: dart run tools/pack_samples.dart [选项]');
  stderr.writeln('  把随附源码拷进 Release 目录的 samples/（安装包随附，使用文档 §7）');
  stderr.writeln('  --release-dir <目录>  Release 目录，默认 $_defaultReleaseDir');
  stderr.writeln('  --sdk-device <目录>   设备端源码，默认 $_defaultSdkDevice');
  stderr.writeln('  --light1 <目录>       示例工程，默认 $_defaultLight1');
  stderr.writeln('                        （可用环境变量 MYHOME_LIGHT1 覆盖）');
  return error == null ? 0 : 2;
}
