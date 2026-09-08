import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../device/device_definition.dart';
import 'studio_controller.dart';

/// devices/ 目录下的设备信息 (扫描结果)。
class DeviceDirInfo {
  const DeviceDirInfo({
    required this.dirName,
    required this.dirPath,
    this.definition,
    this.error,
  });

  /// 目录名 (`devices/<dirName>`)。
  final String dirName;

  /// 目录绝对路径。
  final String dirPath;

  /// 解析后的 device.yaml (null = 解析失败)。
  final DeviceDefinition? definition;

  /// device.yaml 解析失败信息 (definition == null 时有效)。
  final String? error;

  bool get isValid => definition != null;

  /// 是否有可启动的模拟器实现 (当前仅 smart_light 参考设备)。
  bool get hasSimulator => definition?.id == 'smart_light';
}

/// 设备列表控制器：扫描 devices/ 目录，支持移除/删除/新建/打开。
///
/// 移除 = 在设备目录写入 `.removed` 标记 (目录保留)；
/// 删除 = 移除列表并递归删除设备目录 (不可恢复)。
class DeviceListController extends Notifier<List<DeviceDirInfo>> {
  DeviceListController({Directory? devicesRoot, this.opener})
      : _rootOverride = devicesRoot;

  /// 测试注入设备根目录 (生产用 resolvePath 定位项目 devices/)。
  final Directory? _rootOverride;

  /// 打开目录的系统命令 (测试可注入)。
  final Future<void> Function(String path)? opener;

  Directory get _root =>
      _rootOverride ?? Directory(StudioController.resolvePath('devices'));

  /// `.removed` 标记文件名。
  static const String removedMarker = '.removed';

  @override
  List<DeviceDirInfo> build() => _scan();

  /// 重新扫描并刷新列表。
  void refresh() => state = _scan();

  List<DeviceDirInfo> _scan() {
    if (!_root.existsSync()) {
      return const <DeviceDirInfo>[];
    }
    final result = <DeviceDirInfo>[];
    for (final entity in _root.listSync()) {
      if (entity is! Directory) {
        continue;
      }
      // 移除标记：保留目录但不显示
      if (File(p.join(entity.path, removedMarker)).existsSync()) {
        continue;
      }
      final yamlFile = File(p.join(entity.path, 'device.yaml'));
      if (!yamlFile.existsSync()) {
        continue; // 无 device.yaml 的目录不算设备
      }
      final dirName = p.basename(entity.path);
      try {
        result.add(
          DeviceDirInfo(
            dirName: dirName,
            dirPath: entity.path,
            definition: DeviceDefinition.fromYaml(yamlFile.readAsStringSync()),
          ),
        );
      } on DeviceDefinitionException catch (e) {
        result.add(
          DeviceDirInfo(
            dirName: dirName,
            dirPath: entity.path,
            error: e.errors.join('; '),
          ),
        );
      }
    }
    result.sort((a, b) => a.dirName.compareTo(b.dirName));
    return result;
  }

  /// 从列表移除 (写入 .removed 标记，目录保留)。
  void remove(DeviceDirInfo info) {
    File(p.join(info.dirPath, removedMarker)).writeAsStringSync('');
    refresh();
  }

  /// 从列表移除并删除设备目录 (不可恢复)。
  void delete(DeviceDirInfo info) {
    Directory(info.dirPath).deleteSync(recursive: true);
    refresh();
  }

  /// 新建设备：`devices/<id>/` 目录 + device.yaml 骨架。
  /// 返回 null = 成功；非 null = 错误消息。
  String? createDevice({
    required String id,
    required String name,
    required String model,
  }) {
    if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(id)) {
      return 'ID 只能包含小写字母/数字/下划线，且以字母开头';
    }
    final dir = Directory(p.join(_root.path, id));
    if (dir.existsSync()) {
      return '目录已存在: $id';
    }
    try {
      dir.createSync();
      File(p.join(dir.path, 'device.yaml'))
          .writeAsStringSync(_deviceYamlTemplate(id, name, model));
      refresh();
      return null;
    } catch (e) {
      return '创建失败: $e';
    }
  }

  /// 全部设备目录 (含被移除的，供"打开"选择)。
  List<String> allDeviceDirs() {
    if (!_root.existsSync()) {
      return const <String>[];
    }
    final result = <String>[];
    for (final entity in _root.listSync()) {
      if (entity is! Directory) {
        continue;
      }
      if (File(p.join(entity.path, 'device.yaml')).existsSync()) {
        result.add(entity.path);
      }
    }
    result.sort();
    return result;
  }

  /// 在系统文件管理器中打开目录。
  Future<void> openDir(String dirPath) async {
    if (opener != null) {
      await opener!(dirPath);
      return;
    }
    if (Platform.isMacOS) {
      await Process.run('open', <String>[dirPath]);
    } else if (Platform.isWindows) {
      await Process.run('explorer', <String>[dirPath]);
    } else {
      await Process.run('xdg-open', <String>[dirPath]);
    }
  }

  /// device.yaml 骨架 (新建时写入，后续由代码生成器/编辑器完善)。
  static String _deviceYamlTemplate(String id, String name, String model) =>
      '''# $name — 新建设备 (完善后可用代码生成器生成 Dart/C/模拟器)
device:
  id: $id
  name: $name
  model: $model

protocol:
  version: 1

api:
  version: 1

state: {}

commands: []

events: []
''';
}

/// 设备列表 provider。
final deviceListProvider =
    NotifierProvider<DeviceListController, List<DeviceDirInfo>>(
  DeviceListController.new,
);
