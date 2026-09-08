import 'package:yaml/yaml.dart';

/// Device Definition (WORK_V3 §5-§7)：
/// device.yaml 是设备唯一数据源 (Source of Truth)，
/// 生成 Dart API / C API / Simulator / Manifest 的基础。
///
/// 示例结构见 devices/smart_light/device.yaml (WORK_V3 §6)。
class DeviceDefinition {
  const DeviceDefinition({
    required this.id,
    required this.name,
    required this.model,
    required this.protocolVersion,
    required this.apiVersion,
    required this.state,
    required this.commands,
    required this.events,
  });

  /// 设备标识 (全局唯一)。
  final String id;

  /// 展示名称。
  final String name;

  /// 设备型号。
  final String model;

  /// 协议版本 (WORK_V3 §6 protocol.version)。
  final int protocolVersion;

  /// Device API 版本。
  final int apiVersion;

  /// 状态定义 (名称 → 定义)。
  final Map<String, StateDefinition> state;

  /// 命令定义。
  final List<CommandDefinition> commands;

  /// 事件定义。
  final List<EventDefinition> events;

  /// 解析并校验 device.yaml；任何错误抛 [DeviceDefinitionException]
  /// (一次性收集全部错误, WORK_V3 Phase 2)。
  factory DeviceDefinition.fromYaml(String yamlText) {
    Object? root;
    try {
      root = loadYaml(yamlText);
    } on YamlException catch (e) {
      throw DeviceDefinitionException(<String>['YAML 语法错误: ${e.message}']);
    }
    if (root is! Map) {
      throw const DeviceDefinitionException(<String>['顶层必须是 map']);
    }
    return _parse(root.cast<String, dynamic>());
  }

  static DeviceDefinition _parse(Map<String, dynamic> root) {
    final errors = <String>[];

    // ---- device 段 ----
    final device = root['device'];
    if (device is! Map) {
      throw const DeviceDefinitionException(<String>['missing device section']);
    }
    final deviceMap = device.cast<String, dynamic>();
    final id = _string(deviceMap, 'id');
    if (id == null) {
      errors.add('missing device.id');
    }
    final name = _string(deviceMap, 'name') ?? '';
    final model = _string(deviceMap, 'model') ?? '';

    // ---- protocol / api 段 ----
    final protocol = root['protocol'];
    final protocolVersion = protocol is Map
        ? _int(protocol.cast<String, dynamic>(), 'version')
        : null;
    if (protocolVersion == null) {
      errors.add('missing protocol.version');
    }
    final api = root['api'];
    final apiVersion = api is Map
        ? _int(api.cast<String, dynamic>(), 'version')
        : null;
    if (apiVersion == null) {
      errors.add('missing api.version');
    }

    // ---- state 段 ----
    final state = <String, StateDefinition>{};
    final stateMap = root['state'];
    if (stateMap is Map) {
      for (final entry in stateMap.entries) {
        final key = '${entry.key}';
        final value = entry.value;
        if (value is! Map) {
          errors.add('invalid state "$key": 定义必须是 map');
          continue;
        }
        final def = StateDefinition.parse(value.cast<String, dynamic>());
        if (def.error != null) {
          errors.add('invalid state "$key": ${def.error}');
        } else {
          state[key] = def;
        }
      }
    }

    // ---- commands 段 ----
    final commands = <CommandDefinition>[];
    final seenCommands = <String>{};
    final commandsList = root['commands'];
    if (commandsList is List) {
      for (final item in commandsList) {
        if (item is! Map) {
          errors.add('invalid command: 命令定义必须是 map');
          continue;
        }
        final def = CommandDefinition.parse(item.cast<String, dynamic>());
        if (def.name.isEmpty) {
          errors.add('invalid command: missing name');
          continue;
        }
        if (!seenCommands.add(def.name)) {
          errors.add('duplicate command "${def.name}"');
        }
        if (def.error != null) {
          errors.add('invalid command "${def.name}": ${def.error}');
        } else {
          commands.add(def);
        }
      }
    }

    // ---- events 段 ----
    final events = <EventDefinition>[];
    final eventsList = root['events'];
    if (eventsList is List) {
      for (final item in eventsList) {
        if (item is! Map) {
          errors.add('invalid event: 事件定义必须是 map');
          continue;
        }
        final name = _string(item.cast<String, dynamic>(), 'name');
        if (name == null) {
          errors.add('invalid event: missing name');
        } else {
          events.add(EventDefinition(name: name));
        }
      }
    }

    if (errors.isNotEmpty) {
      throw DeviceDefinitionException(errors);
    }
    return DeviceDefinition(
      id: id!,
      name: name,
      model: model,
      protocolVersion: protocolVersion!,
      apiVersion: apiVersion!,
      state: state,
      commands: commands,
      events: events,
    );
  }

  static String? _string(Map<String, dynamic> map, String key) {
    final value = map[key];
    return value is String ? value : null;
  }

  static int? _int(Map<String, dynamic> map, String key) {
    final value = map[key];
    return value is int ? value : null;
  }
}

/// 支持的参数/状态类型 (WORK_V3 §6)。
enum ValueType {
  boolType('bool'),
  uint8('uint8'),
  uint16('uint16'),
  int32('int32'),
  float('float'),
  string('string');

  const ValueType(this.yamlName);

  /// device.yaml 中的类型名。
  final String yamlName;

  static ValueType? tryParse(String? name) {
    for (final type in ValueType.values) {
      if (type.yamlName == name) {
        return type;
      }
    }
    return null;
  }
}

/// 状态字段定义。
class StateDefinition {
  const StateDefinition({required this.type, this.min, this.max, this.error});

  final ValueType type;
  final num? min;
  final num? max;

  /// 解析错误 (null = 合法)。
  final String? error;

  factory StateDefinition.parse(Map<String, dynamic> map) {
    final type = ValueType.tryParse(map['type'] is String ? map['type'] as String : null);
    if (type == null) {
      return StateDefinition(
        type: ValueType.string,
        error: 'unsupported type "${map['type']}"',
      );
    }
    final min = map['min'];
    final max = map['max'];
    if (min != null && min is! num) {
      return const StateDefinition(
        type: ValueType.string,
        error: 'min 必须是数字',
      );
    }
    if (max != null && max is! num) {
      return const StateDefinition(
        type: ValueType.string,
        error: 'max 必须是数字',
      );
    }
    if (min != null && max != null && min > max) {
      return StateDefinition(
        type: type,
        error: 'min ($min) 不能大于 max ($max)',
      );
    }
    return StateDefinition(
      type: type,
      min: min is num ? min : null,
      max: max is num ? max : null,
    );
  }
}

/// 命令定义。
class CommandDefinition {
  const CommandDefinition({
    required this.name,
    required this.params,
    this.error,
  });

  final String name;
  final Map<String, ParamDefinition> params;

  /// 解析错误 (null = 合法)。
  final String? error;

  factory CommandDefinition.parse(Map<String, dynamic> map) {
    final name = map['name'];
    if (name is! String || name.isEmpty) {
      return const CommandDefinition(name: '', params: {}, error: 'missing name');
    }
    final params = <String, ParamDefinition>{};
    final paramsMap = map['params'];
    if (paramsMap != null && paramsMap is! Map) {
      return CommandDefinition(
        name: name,
        params: params,
        error: 'params 必须是 map',
      );
    }
    if (paramsMap is Map) {
      for (final entry in paramsMap.entries) {
        final key = '${entry.key}';
        final value = entry.value;
        if (value is! Map) {
          return CommandDefinition(
            name: name,
            params: params,
            error: 'invalid parameter "$key": 参数定义必须是 map',
          );
        }
        final def = ParamDefinition.parse(value.cast<String, dynamic>());
        if (def.error != null) {
          return CommandDefinition(
            name: name,
            params: params,
            error: 'invalid parameter "$key": ${def.error}',
          );
        }
        params[key] = def;
      }
    }
    return CommandDefinition(name: name, params: params);
  }
}

/// 命令参数定义。
class ParamDefinition {
  const ParamDefinition({required this.type, this.min, this.max, this.error});

  final ValueType type;
  final num? min;
  final num? max;

  /// 解析错误 (null = 合法)。
  final String? error;

  factory ParamDefinition.parse(Map<String, dynamic> map) {
    final type = ValueType.tryParse(map['type'] is String ? map['type'] as String : null);
    if (type == null) {
      return ParamDefinition(
        type: ValueType.string,
        error: 'unsupported type "${map['type']}"',
      );
    }
    final min = map['min'];
    final max = map['max'];
    if ((min != null && min is! num) || (max != null && max is! num)) {
      return ParamDefinition(
        type: type,
        error: 'min/max 必须是数字',
      );
    }
    if (min != null && max != null && min > max) {
      return ParamDefinition(
        type: type,
        error: 'min ($min) 不能大于 max ($max)',
      );
    }
    return ParamDefinition(
      type: type,
      min: min is num ? min : null,
      max: max is num ? max : null,
    );
  }
}

/// 事件定义。
class EventDefinition {
  const EventDefinition({required this.name});

  final String name;
}

/// 设备定义解析/校验异常 (WORK_V3 Phase 2：一次收集全部错误)。
class DeviceDefinitionException implements Exception {
  const DeviceDefinitionException(this.errors);

  /// 全部错误消息 (每条一句，直接可读)。
  final List<String> errors;

  @override
  String toString() => 'DeviceDefinitionException:\n${errors.join('\n')}';
}
