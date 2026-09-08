import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
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

/// 设备列表控制器：扫描 devices/ 目录，支持移除/删除/新建/导入。
///
/// 移除 = 在设备目录写入 `.removed` 标记 (目录保留)；
/// 删除 = 移除列表并递归删除设备目录 (不可恢复)；
/// 导入 = 目录选择器选中设备目录后加入列表 (devices/ 内恢复显示，
/// devices/ 外记入 `.studio_imports.json` 持久化)。
class DeviceListController extends Notifier<List<DeviceDirInfo>> {
  DeviceListController({Directory? devicesRoot, this.picker})
      : _rootOverride = devicesRoot;

  /// 测试注入设备根目录 (生产用 resolvePath 定位项目 devices/)。
  final Directory? _rootOverride;

  /// 目录选择器 (测试可注入；默认 file_picker 原生目录选择)。
  final Future<String?> Function()? picker;

  Directory get _root =>
      _rootOverride ?? Directory(StudioController.resolvePath('devices'));

  /// `.removed` 标记文件名。
  static const String removedMarker = '.removed';

  /// 外部导入目录持久化文件名 (devices/ 根下)。
  static const String importsFileName = '.studio_imports.json';

  /// 外部导入的设备目录绝对路径。
  final List<String> _imports = <String>[];

  @override
  List<DeviceDirInfo> build() {
    _loadImports();
    return _scan();
  }

  /// 重新扫描并刷新列表。
  void refresh() => state = _scan();

  void _loadImports() {
    _imports.clear();
    final file = File(p.join(_root.path, importsFileName));
    if (!file.existsSync()) {
      return;
    }
    try {
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final list = data['imports'];
      if (list is List) {
        for (final item in list) {
          // 目录已不存在的不再显示
          if (item is String && Directory(item).existsSync()) {
            _imports.add(item);
          }
        }
      }
    } catch (_) {
      // 坏导入文件：忽略
    }
  }

  void _saveImports() {
    final root = Directory(_root.path);
    if (!root.existsSync()) {
      root.createSync(recursive: true);
    }
    File(p.join(_root.path, importsFileName)).writeAsStringSync(
      jsonEncode(<String, dynamic>{'imports': _imports}),
    );
  }

  List<DeviceDirInfo> _scan() {
    final result = <DeviceDirInfo>[];
    if (_root.existsSync()) {
      for (final entity in _root.listSync()) {
        if (entity is! Directory) {
          continue;
        }
        // 移除标记：保留目录但不显示
        if (File(p.join(entity.path, removedMarker)).existsSync()) {
          continue;
        }
        final info = _readDir(entity.path);
        if (info != null) {
          result.add(info);
        }
      }
    }
    // 外部导入目录
    final seen = result.map((i) => i.dirPath).toSet();
    for (final dirPath in _imports) {
      if (File(p.join(dirPath, removedMarker)).existsSync()) {
        continue;
      }
      final info = _readDir(dirPath);
      if (info != null && seen.add(info.dirPath)) {
        result.add(info);
      }
    }
    result.sort((a, b) => a.dirName.compareTo(b.dirName));
    return result;
  }

  /// 读取设备目录信息；无 device.yaml 返回 null。
  DeviceDirInfo? _readDir(String dirPath) {
    final yamlFile = File(p.join(dirPath, 'device.yaml'));
    if (!yamlFile.existsSync()) {
      return null; // 无 device.yaml 的目录不算设备
    }
    final dirName = p.basename(dirPath);
    try {
      return DeviceDirInfo(
        dirName: dirName,
        dirPath: dirPath,
        definition: DeviceDefinition.fromYaml(yamlFile.readAsStringSync()),
      );
    } on DeviceDefinitionException catch (e) {
      return DeviceDirInfo(
        dirName: dirName,
        dirPath: dirPath,
        error: e.errors.join('; '),
      );
    }
  }

  /// 从列表移除 (写入 .removed 标记，目录保留)。
  void remove(DeviceDirInfo info) {
    File(p.join(info.dirPath, removedMarker)).writeAsStringSync('');
    refresh();
  }

  /// 从列表移除并删除设备目录 (不可恢复)。
  void delete(DeviceDirInfo info) {
    Directory(info.dirPath).deleteSync(recursive: true);
    _imports.remove(info.dirPath);
    _saveImports();
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

  /// 弹出目录选择器并导入所选设备目录。
  /// 返回 null = 成功或用户取消；非 null = 错误消息。
  Future<String?> pickAndImport() async {
    final pick = picker ?? () => FilePicker.getDirectoryPath();
    final dir = await pick();
    if (dir == null || dir.isEmpty) {
      return null; // 用户取消
    }
    return importDevice(dir);
  }

  /// 导入设备目录：devices/ 内 → 恢复显示 (删除 .removed 标记)；
  /// devices/ 外 → 记入导入列表并持久化。返回 null = 成功。
  String? importDevice(String dirPath) {
    if (!Directory(dirPath).existsSync() ||
        !File(p.join(dirPath, 'device.yaml')).existsSync()) {
      return '所选目录不含 device.yaml，不是设备目录';
    }
    final rel = p.relative(dirPath, from: _root.path);
    final insideRoot = rel != '..' && !rel.startsWith('..${p.separator}');
    if (insideRoot) {
      // 恢复显示：删除 .removed 标记
      final marker = File(p.join(dirPath, removedMarker));
      if (marker.existsSync()) {
        marker.deleteSync();
      }
    } else if (!_imports.contains(dirPath)) {
      _imports.add(dirPath);
      _saveImports();
    }
    refresh();
    return null;
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
