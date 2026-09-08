import 'dart:io';

import 'package:myhome/device/device_definition.dart';

/// Device CLI (WORK_V3 §43)：设备定义校验等开发工具。
///
/// 用法：
/// ```bash
/// dart run tools/device_cli.dart validate devices/smart_light/device.yaml
/// ```
/// 退出码：0 = PASS；1 = ERROR；2 = 用法错误。
Future<void> main(List<String> args) async {
  if (args.length < 2 || args[0] != 'validate') {
    stderr.writeln('用法: device_cli validate <device.yaml>');
    exit(2);
  }
  final path = args[1];
  final String text;
  try {
    text = await File(path).readAsString();
  } on FileSystemException {
    stderr.writeln('ERROR: 文件不存在: $path');
    exit(1);
  }
  try {
    final def = DeviceDefinition.fromYaml(text);
    stdout.writeln(
      'PASS: ${def.id} (${def.name}, protocol=${def.protocolVersion}, '
      'state=${def.state.length}, commands=${def.commands.length}, '
      'events=${def.events.length})',
    );
    exit(0);
  } on DeviceDefinitionException catch (e) {
    stderr.writeln('ERROR:');
    for (final error in e.errors) {
      stderr.writeln('  - $error');
    }
    exit(1);
  }
}
