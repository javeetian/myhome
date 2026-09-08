import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:myhome/device/device_definition.dart';
import 'package:myhome/device/device_manifest.dart';
import 'package:myhome/ui_runtime/ui_package.dart';
import 'package:myhome/ui_runtime/ui_package_validator.dart';
import 'package:path/path.dart' as p;

/// Device CLI (WORK_V3 §43)：设备开发工具链。
///
/// 用法：
/// ```bash
/// dart run tools/device_cli.dart validate <device.yaml>
/// dart run tools/device_cli.dart ui build <ui目录> [输出.ui.pkg]
/// dart run tools/device_cli.dart ui validate <ui.pkg>
/// ```
/// 退出码：0 = PASS；1 = ERROR；2 = 用法错误。
Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    _usage();
    exit(2);
  }
  switch (args[0]) {
    case 'validate':
      exit(await _validateDefinition(args));
    case 'ui':
      exit(await _uiCommand(args.sublist(1)));
    default:
      _usage();
      exit(2);
  }
}

void _usage() {
  stderr.writeln('用法:');
  stderr.writeln('  device validate <device.yaml>         校验设备定义 (Phase 2)');
  stderr.writeln('  device ui build <ui目录> [输出]       打包 UI 目录为 ui.pkg (Phase 13)');
  stderr.writeln('  device ui validate <ui.pkg>           校验 ui.pkg (Phase 14)');
}

/// Phase 2：设备定义校验。
Future<int> _validateDefinition(List<String> args) async {
  if (args.length < 2) {
    _usage();
    return 2;
  }
  final path = args[1];
  final String text;
  try {
    text = await File(path).readAsString();
  } on FileSystemException {
    stderr.writeln('ERROR: 文件不存在: $path');
    return 1;
  }
  try {
    final def = DeviceDefinition.fromYaml(text);
    stdout.writeln(
      'PASS: ${def.id} (${def.name}, protocol=${def.protocolVersion}, '
      'state=${def.state.length}, commands=${def.commands.length}, '
      'events=${def.events.length})',
    );
    return 0;
  } on DeviceDefinitionException catch (e) {
    stderr.writeln('ERROR:');
    for (final error in e.errors) {
      stderr.writeln('  - $error');
    }
    return 1;
  }
}

/// Phase 13/14：ui build / ui validate。
Future<int> _uiCommand(List<String> args) async {
  if (args.isEmpty) {
    _usage();
    return 2;
  }
  switch (args[0]) {
    case 'build':
      return _uiBuild(args.sublist(1));
    case 'validate':
      return _uiValidate(args.sublist(1));
    default:
      _usage();
      return 2;
  }
}

/// Phase 13：目录 → ui.pkg。
Future<int> _uiBuild(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('用法: device ui build <ui目录> [输出.ui.pkg]');
    return 2;
  }
  final sourceDir = Directory(args[0]);
  if (!sourceDir.existsSync()) {
    stderr.writeln('ERROR: UI 目录不存在: ${args[0]}');
    return 1;
  }
  // 收集目录下全部文件 (相对路径 → 内容)
  final files = <String, Uint8List>{};
  for (final entity in sourceDir.listSync(recursive: true)) {
    if (entity is! File) {
      continue;
    }
    final rel = p
        .relative(entity.path, from: sourceDir.path)
        .replaceAll('\\', '/');
    files[rel] = Uint8List.fromList(entity.readAsBytesSync());
  }
  if (!files.containsKey('manifest.json')) {
    stderr.writeln('ERROR: UI 目录缺少 manifest.json');
    return 1;
  }

  // 校验源 manifest (构建前检查)
  final manifest = DeviceManifest.fromJson(
    jsonDecode(utf8.decode(files['manifest.json']!)) as Map<String, dynamic>,
  );
  if (!files.containsKey(manifest.entry)) {
    stderr.writeln('ERROR: UI package entry not found: ${manifest.entry}');
    return 1;
  }

  // 打包
  final pkg = UiPackage.pack(files);

  // 输出 (默认 <ui目录>/../build/ui.pkg)
  final outPath = args.length > 1
      ? args[1]
      : p.join(sourceDir.parent.path, 'build', 'ui.pkg');
  final outFile = File(outPath);
  outFile.parent.createSync(recursive: true);
  outFile.writeAsBytesSync(pkg);

  stdout.writeln(
    'PASS: ui.pkg ($outPath) '
    '${pkg.length} bytes, ${files.length} files, '
    'version=${manifest.uiVersion}, entry=${manifest.entry}, '
    'sha256=${sha256.convert(pkg).toString().substring(0, 16)}...',
  );
  return 0;
}

/// Phase 14：ui.pkg 校验。
Future<int> _uiValidate(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('用法: device ui validate <ui.pkg>');
    return 2;
  }
  final file = File(args[0]);
  if (!file.existsSync()) {
    stderr.writeln('ERROR: 文件不存在: ${args[0]}');
    return 1;
  }
  final errors =
      UiPackageValidator.validate(Uint8List.fromList(file.readAsBytesSync()));
  if (errors.isNotEmpty) {
    stderr.writeln('ERROR:');
    for (final error in errors) {
      stderr.writeln('  - $error');
    }
    return 1;
  }
  stdout.writeln('PASS: ${args[0]}');
  return 0;
}
