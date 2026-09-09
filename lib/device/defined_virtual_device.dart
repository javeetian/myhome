import 'dart:convert';
import 'dart:typed_data';

import '../protocol/protocol_messages.dart';
import '../ui_runtime/ui_package.dart';
import 'device_definition.dart';
import 'device_manifest.dart';
import 'protocol_device.dart';

/// 由 device.yaml 驱动的通用模拟设备 (WORK_V3 定义驱动)：
/// 任何通过 `新建设备` 模板 (或遵循同一约定) 的设备都能直接模拟运行，
/// 无需为每个设备编写专用模拟器类。
///
/// 约定：
/// - 命令名最后一段 (去掉 `set_` 前缀) = 状态键：`light.set_brightness` → `brightness`
/// - 参数名：`value` 或与状态键同名
/// - 初始状态：bool → false；数值 → min ?? 0；string → ''
/// - 事件：取定义中第一个事件名 (模板为 `<id>.state_changed`)
///
/// 更复杂的设备行为 (传感器、定时任务) 用专用模拟器类实现
/// (如 VirtualLight)，本类覆盖模板型设备的完整闭环。
class DefinedVirtualDevice extends ProtocolDevice {
  DefinedVirtualDevice(this.definition, {this.uiPkgBytes});

  final DeviceDefinition definition;

  /// 外部 UI 包 (Studio 现场打包该设备的 ui 目录)。
  final Uint8List? uiPkgBytes;

  Map<String, Uint8List>? _uiFiles;
  int _stateVersion = 0;
  final Map<String, dynamic> _state = <String, dynamic>{};

  @override
  String get deviceId => definition.id;

  @override
  String get name => definition.name;

  @override
  String get uiVersion {
    final manifestBytes = resourceBytes('manifest.json');
    if (manifestBytes != null) {
      try {
        return DeviceManifest.fromJson(
          jsonDecode(utf8.decode(manifestBytes)) as Map<String, dynamic>,
        ).uiVersion;
      } catch (_) {
        // 坏 manifest：回退
      }
    }
    return '0.0.0';
  }

  @override
  DeviceHelloAck helloAckFor(DeviceHello hello) => DeviceHelloAck(
        requestId: hello.requestId,
        protocolVersion: definition.protocolVersion,
        deviceType: definition.id,
        deviceModel: definition.model,
        firmwareVersion: '0.1.0',
        uiVersion: uiVersion,
        capabilities: definition.state.keys.toList(),
      );

  @override
  Future<void> onDeviceConnect() async {
    _stateVersion = 1;
    // 初始状态：bool → false；数值 → min ?? 0；string → ''
    for (final entry in definition.state.entries) {
      _state[entry.key] = switch (entry.value.type) {
        ValueType.boolType => false,
        ValueType.uint8 || ValueType.uint16 || ValueType.int32 =>
          entry.value.min ?? 0,
        ValueType.float => (entry.value.min ?? 0).toDouble(),
        ValueType.string => '',
      };
    }
    pushState(currentState);
  }

  @override
  Future<void> onDeviceDisconnect() async {}

  @override
  DeviceState get currentState => DeviceState(
        version: _stateVersion,
        state: Map<String, dynamic>.unmodifiable(_state),
      );

  @override
  Future<DeviceResponse?> handleCommand(DeviceCommand command) async {
    final cmdDef = definition.commands
        .where((c) => c.name == command.cmd)
        .firstOrNull;
    if (cmdDef == null) {
      return DeviceResponse(
        requestId: command.requestId,
        status: 'error',
        error: DeviceError(code: 3002, message: 'unknown command "${command.cmd}"'),
      );
    }
    // 参数校验 (类型 + 范围, §10.5)
    for (final entry in cmdDef.params.entries) {
      final value = command.params[entry.key];
      final error = _validateParam(entry.key, entry.value, value);
      if (error != null) {
        return DeviceResponse(
          requestId: command.requestId,
          status: 'error',
          error: error,
        );
      }
    }
    // 状态更新：命令名最后一段 (去掉 set_ 前缀) = 状态键
    // 如 light.set_brightness → brightness；参数名 value 或与状态键同名
    final lastSegment = command.cmd.split('.').last;
    final stateKey = lastSegment.startsWith('set_')
        ? lastSegment.substring(4)
        : lastSegment;
    if (definition.state.containsKey(stateKey)) {
      final value =
          command.params['value'] ?? command.params[stateKey];
      _state[stateKey] = switch (definition.state[stateKey]!.type) {
        ValueType.boolType => value as bool,
        ValueType.uint8 || ValueType.uint16 || ValueType.int32 =>
          (value as num).toInt(),
        ValueType.float => (value as num).toDouble(),
        ValueType.string => value as String,
      };
    }
    final snapshot =
        DeviceState(version: ++_stateVersion, state: Map<String, dynamic>.unmodifiable(_state));
    pushState(snapshot);
    if (definition.events.isNotEmpty) {
      sendEvent(definition.events.first.name, <String, dynamic>{
        'version': snapshot.version,
        'state': snapshot.state,
      });
    }
    return DeviceResponse(
      requestId: command.requestId,
      data: <String, dynamic>{'version': snapshot.version},
    );
  }

  DeviceError? _validateParam(String key, ParamDefinition def, Object? value) {
    switch (def.type) {
      case ValueType.boolType:
        if (value is! bool) {
          return DeviceError(code: 3001, message: 'invalid $key');
        }
      case ValueType.uint8:
      case ValueType.uint16:
      case ValueType.int32:
        if (value is! num) {
          return DeviceError(code: 3001, message: 'invalid $key');
        }
        final v = value.toInt();
        if ((def.min != null && v < def.min!) ||
            (def.max != null && v > def.max!)) {
          return DeviceError(
              code: 3001, message: '$key 越界 [${def.min}, ${def.max}]');
        }
      case ValueType.float:
        if (value is! num) {
          return DeviceError(code: 3001, message: 'invalid $key');
        }
      case ValueType.string:
        if (value is! String) {
          return DeviceError(code: 3001, message: 'invalid $key');
        }
    }
    return null;
  }

  @override
  Uint8List? resourceBytes(String path) {
    if (uiPkgBytes == null) {
      return null;
    }
    if (path == 'ui.pkg') {
      return uiPkgBytes;
    }
    _uiFiles ??= UiPackage.unpack(uiPkgBytes!);
    return _uiFiles![path];
  }
}
