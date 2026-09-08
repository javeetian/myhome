import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:myhome/device/device_definition.dart';
import 'package:myhome/device/device_manifest.dart';
import 'package:myhome/tools/code_generator.dart';
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
/// dart run tools/device_cli.dart generate <device.yaml> [输出目录]
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
    case 'generate':
      exit(await _generateCommand(args.sublist(1)));
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
  stderr.writeln('  device generate <device.yaml> [目录]  生成多端代码 (Phase 25)');
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

/// Phase 13/14/37：ui build / ui validate / ui watch。
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
    case 'watch':
      return _uiWatch(args.sublist(1));
    default:
      _usage();
      return 2;
  }
}

/// Phase 37：监听 UI 源目录 → 自动重打包 (配合 Studio 自动重载)。
Future<int> _uiWatch(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('用法: device ui watch <ui目录> [输出.ui.pkg]');
    return 2;
  }
  final sourceDir = args[0];
  final outPath = args.length > 1
      ? args[1]
      : p.join(p.dirname(sourceDir), 'build', 'ui.pkg');
  if (!Directory(sourceDir).existsSync()) {
    stderr.writeln('ERROR: UI 目录不存在: $sourceDir');
    return 1;
  }
  stdout.writeln('WATCH: $sourceDir → $outPath (Ctrl+C 退出)');
  var exitCode = await _uiBuildOnce(sourceDir, outPath);
  if (exitCode != 0) {
    return exitCode;
  }
  await for (final event in Directory(sourceDir).watch(recursive: true)) {
    final name = p.basename(event.path);
    if (name.startsWith('.')) {
      continue; // 编辑器临时文件
    }
    stdout.writeln(
      '${DateTime.now().toIso8601String()} changed: $name → 重新打包',
    );
    exitCode = await _uiBuildOnce(sourceDir, outPath);
    if (exitCode != 0) {
      stderr.writeln('WARN: 打包失败，继续监听…');
    }
  }
  return 0;
}

/// 构建一次：目录 → ui.pkg。返回退出码。
Future<int> _uiBuildOnce(String sourceDir, String outPath) async {
  final files = <String, Uint8List>{};
  for (final entity in Directory(sourceDir).listSync(recursive: true)) {
    if (entity is! File) {
      continue;
    }
    final rel =
        p.relative(entity.path, from: sourceDir).replaceAll('\\', '/');
    files[rel] = Uint8List.fromList(entity.readAsBytesSync());
  }
  if (!files.containsKey('manifest.json')) {
    stderr.writeln('ERROR: UI 目录缺少 manifest.json');
    return 1;
  }
  final DeviceManifest manifest;
  try {
    manifest = DeviceManifest.fromJson(
      jsonDecode(utf8.decode(files['manifest.json']!)) as Map<String, dynamic>,
    );
  } catch (e) {
    stderr.writeln('ERROR: Invalid manifest: $e');
    return 1;
  }
  if (!files.containsKey(manifest.entry)) {
    stderr.writeln('ERROR: UI package entry not found: ${manifest.entry}');
    return 1;
  }
  final pkg = UiPackage.pack(files);
  final outFile = File(outPath);
  outFile.parent.createSync(recursive: true);
  outFile.writeAsBytesSync(pkg);
  stdout.writeln(
    'PASS: ui.pkg ($outPath) ${pkg.length} bytes, ${files.length} files, '
    'version=${manifest.uiVersion}, sha256=${sha256.convert(pkg).toString().substring(0, 16)}...',
  );
  return 0;
}

/// Phase 25：device.yaml → 多端代码生成。
Future<int> _generateCommand(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('用法: device generate <device.yaml> [输出目录]');
    return 2;
  }
  final file = File(args[0]);
  if (!file.existsSync()) {
    stderr.writeln('ERROR: 文件不存在: ${args[0]}');
    return 1;
  }
  final DeviceDefinition def;
  try {
    def = DeviceDefinition.fromYaml(await file.readAsString());
  } on DeviceDefinitionException catch (e) {
    stderr.writeln('ERROR: 设备定义非法:');
    for (final error in e.errors) {
      stderr.writeln('  - $error');
    }
    return 1;
  }
  final outDir = Directory(args.length > 1
      ? args[1]
      : p.join(file.parent.path, 'generated'));
  final files = CodeGenerator.generate(def);
  for (final entry in files.entries) {
    final target = File(p.join(outDir.path, entry.key));
    target.parent.createSync(recursive: true);
    target.writeAsStringSync(entry.value);
  }
  stdout.writeln('PASS: 生成 ${files.length} 个文件到 ${outDir.path}:');
  for (final path in files.keys) {
    stdout.writeln('  - $path');
  }
  return 0;
}

/// Phase 13：目录 → ui.pkg。
Future<int> _uiBuild(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('用法: device ui build <ui目录> [输出.ui.pkg]');
    return 2;
  }
  final sourceDir = args[0];
  if (!Directory(sourceDir).existsSync()) {
    stderr.writeln('ERROR: UI 目录不存在: $sourceDir');
    return 1;
  }
  final outPath = args.length > 1
      ? args[1]
      : p.join(p.dirname(sourceDir), 'build', 'ui.pkg');
  return _uiBuildOnce(sourceDir, outPath);
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
