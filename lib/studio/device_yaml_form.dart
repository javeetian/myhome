import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device/device_definition.dart';
import 'opened_files_controller.dart';

/// device.yaml 可视化表单 (UI 视图, WORK_V3 §30 扩展)：
/// 字段编辑 + 状态/命令/事件可增删 → 保存写回磁盘 → 编辑器自动重载。
/// 解析失败的 yaml 显示错误提示，切回源码视图修复。
class DeviceYamlForm extends ConsumerStatefulWidget {
  const DeviceYamlForm({super.key, required this.path});

  final String path;

  @override
  ConsumerState<DeviceYamlForm> createState() => _DeviceYamlFormState();
}

class _StateField {
  _StateField({required String name})
      : nameController = TextEditingController(text: name);

  final TextEditingController nameController;
  ValueType type = ValueType.boolType;
  final TextEditingController minController = TextEditingController();
  final TextEditingController maxController = TextEditingController();

  void dispose() {
    nameController.dispose();
    minController.dispose();
    maxController.dispose();
  }
}

class _ParamField {
  _ParamField({required String name})
      : nameController = TextEditingController(text: name);

  final TextEditingController nameController;
  ValueType type = ValueType.boolType;
  final TextEditingController minController = TextEditingController();
  final TextEditingController maxController = TextEditingController();

  void dispose() {
    nameController.dispose();
    minController.dispose();
    maxController.dispose();
  }
}

class _CommandField {
  _CommandField({required String name})
      : nameController = TextEditingController(text: name);

  final TextEditingController nameController;
  final List<_ParamField> params = <_ParamField>[];

  void dispose() {
    nameController.dispose();
    for (final param in params) {
      param.dispose();
    }
  }
}

class _DeviceYamlFormState extends ConsumerState<DeviceYamlForm> {
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();
  int _protocolVersion = 1;
  int _apiVersion = 1;

  final List<_StateField> _states = <_StateField>[];
  final List<_CommandField> _commands = <_CommandField>[];
  final List<TextEditingController> _events = <TextEditingController>[];

  String? _parseError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final text = File(widget.path).readAsStringSync();
    try {
      final def = DeviceDefinition.fromYaml(text);
      _idController.text = def.id;
      _nameController.text = def.name;
      _modelController.text = def.model;
      _protocolVersion = def.protocolVersion;
      _apiVersion = def.apiVersion;
      for (final entry in def.state.entries) {
        final field = _StateField(name: entry.key)
          ..type = entry.value.type
          ..minController.text = entry.value.min?.toString() ?? ''
          ..maxController.text = entry.value.max?.toString() ?? '';
        _states.add(field);
      }
      for (final command in def.commands) {
        final field = _CommandField(name: command.name);
        for (final param in command.params.entries) {
          field.params.add(_ParamField(name: param.key)
            ..type = param.value.type
            ..minController.text = param.value.min?.toString() ?? ''
            ..maxController.text = param.value.max?.toString() ?? '');
        }
        _commands.add(field);
      }
      for (final event in def.events) {
        _events.add(TextEditingController(text: event.name));
      }
    } on DeviceDefinitionException catch (e) {
      _parseError = e.errors.join('\n');
    }
  }

  @override
  void dispose() {
    _idController.dispose();
    _nameController.dispose();
    _modelController.dispose();
    for (final field in _states) {
      field.dispose();
    }
    for (final command in _commands) {
      command.dispose();
    }
    for (final controller in _events) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final error = _validate();
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    File(widget.path).writeAsStringSync(_toYaml());
    ref.read(openedFilesProvider.notifier).reloadActive();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存 device.yaml')),
      );
    }
  }

  String? _validate() {
    final id = _idController.text.trim();
    if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(id)) {
      return 'ID 只能包含小写字母/数字/下划线，且以字母开头';
    }
    if (_nameController.text.trim().isEmpty) {
      return '名称不能为空';
    }
    for (final field in _states) {
      if (field.nameController.text.trim().isEmpty) {
        return '状态字段名不能为空';
      }
    }
    for (final command in _commands) {
      if (command.nameController.text.trim().isEmpty) {
        return '命令名不能为空';
      }
      for (final param in command.params) {
        if (param.nameController.text.trim().isEmpty) {
          return '参数名不能为空';
        }
      }
    }
    return null;
  }

  String _toYaml() {
    final buffer = StringBuffer()
      ..writeln('# ${_nameController.text.trim()}')
      ..writeln('device:')
      ..writeln('  id: ${_idController.text.trim()}')
      ..writeln('  name: ${_nameController.text.trim()}')
      ..writeln('  model: ${_modelController.text.trim()}')
      ..writeln()
      ..writeln('protocol:')
      ..writeln('  version: $_protocolVersion')
      ..writeln()
      ..writeln('api:')
      ..writeln('  version: $_apiVersion')
      ..writeln();
    if (_states.isNotEmpty) {
      buffer.writeln('state:');
      for (final field in _states) {
        buffer.writeln('  ${field.nameController.text.trim()}:');
        buffer.writeln('    type: ${field.type.yamlName}');
        _writeRange(buffer, field, indent: 4);
      }
      buffer.writeln();
    } else {
      buffer.writeln('state: {}');
      buffer.writeln();
    }
    if (_commands.isNotEmpty) {
      buffer.writeln('commands:');
      for (final command in _commands) {
        buffer.writeln('  - name: ${command.nameController.text.trim()}');
        if (command.params.isNotEmpty) {
          buffer.writeln('    params:');
          for (final param in command.params) {
            buffer.writeln('      ${param.nameController.text.trim()}:');
            buffer.writeln('        type: ${param.type.yamlName}');
            _writeRange(buffer, param, indent: 8);
          }
        }
      }
      buffer.writeln();
    } else {
      buffer.writeln('commands: []');
      buffer.writeln();
    }
    if (_events.isNotEmpty) {
      buffer.writeln('events:');
      for (final controller in _events) {
        buffer.writeln('  - name: ${controller.text.trim()}');
      }
    } else {
      buffer.writeln('events: []');
    }
    return buffer.toString();
  }

  void _writeRange(StringBuffer buffer, dynamic field, {required int indent}) {
    final min = field.minController.text.trim();
    final max = field.maxController.text.trim();
    if (min.isNotEmpty) {
      buffer.writeln('${' ' * indent}min: $min');
    }
    if (max.isNotEmpty) {
      buffer.writeln('${' ' * indent}max: $max');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_parseError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.error_outline, size: 40, color: Colors.orange),
              const SizedBox(height: 8),
              const Text('device.yaml 解析失败，切回源码视图修复'),
              const SizedBox(height: 8),
              Text(
                _parseError!,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _card('设备信息', <Widget>[
            _textField('ID', _idController),
            _textField('名称', _nameController),
            _textField('型号', _modelController),
            Row(
              children: <Widget>[
                Expanded(
                  child: _numberField('协议版本', _protocolVersion,
                      (v) => setState(() => _protocolVersion = v)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _numberField('API 版本', _apiVersion,
                      (v) => setState(() => _apiVersion = v)),
                ),
              ],
            ),
          ]),
          _card('状态字段', <Widget>[
            for (var i = 0; i < _states.length; i++)
              _stateRow(_states[i], () => setState(() {
                    _states[i].dispose();
                    _states.removeAt(i);
                  })),
            TextButton.icon(
              onPressed: () =>
                  setState(() => _states.add(_StateField(name: 'new_field'))),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('添加状态'),
            ),
          ]),
          _card('命令', <Widget>[
            for (var i = 0; i < _commands.length; i++)
              _commandRow(_commands[i], () => setState(() {
                    _commands[i].dispose();
                    _commands.removeAt(i);
                  })),
            TextButton.icon(
              onPressed: () => setState(
                  () => _commands.add(_CommandField(name: 'device.new_cmd'))),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('添加命令'),
            ),
          ]),
          _card('事件', <Widget>[
            for (var i = 0; i < _events.length; i++)
              Row(
                children: <Widget>[
                  Expanded(child: _textField('事件名', _events[i])),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 16),
                    onPressed: () => setState(() {
                      _events[i].dispose();
                      _events.removeAt(i);
                    }),
                  ),
                ],
              ),
            TextButton.icon(
              onPressed: () =>
                  setState(() => _events.add(TextEditingController())),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('添加事件'),
            ),
          ]),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save, size: 16),
            label: const Text('保存 device.yaml'),
          ),
        ],
      ),
    );
  }

  Widget _card(String title, List<Widget> children) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 12),
              for (final child in children) ...<Widget>[
                child,
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      );

  Widget _textField(String label, TextEditingController controller) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
      );

  Widget _numberField(String label, int value, ValueChanged<int> onChanged) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: TextField(
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          controller: TextEditingController(text: '$value'),
          onChanged: (text) {
            final v = int.tryParse(text);
            if (v != null) {
              onChanged(v);
            }
          },
        ),
      );

  Widget _typeDropdown(
    ValueType current,
    ValueChanged<ValueType> onChanged,
  ) =>
      DropdownButton<ValueType>(
        value: current,
        isDense: true,
        items: <DropdownMenuItem<ValueType>>[
          for (final type in ValueType.values)
            DropdownMenuItem<ValueType>(
              value: type,
              child: Text(type.yamlName, style: const TextStyle(fontSize: 12)),
            ),
        ],
        onChanged: (type) {
          if (type != null) {
            onChanged(type);
          }
        },
      );

  Widget _rangeFields(
    TextEditingController min,
    TextEditingController max,
  ) =>
      Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: min,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'min',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: max,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'max',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ],
      );

  Widget _stateRow(_StateField field, VoidCallback onDelete) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: _textField('字段名', field.nameController)),
              const SizedBox(width: 8),
              _typeDropdown(field.type,
                  (type) => setState(() => field.type = type)),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 16),
                onPressed: onDelete,
              ),
            ],
          ),
          if (field.type != ValueType.boolType &&
              field.type != ValueType.string)
            _rangeFields(field.minController, field.maxController),
          const Divider(height: 16),
        ],
      );

  Widget _commandRow(_CommandField command, VoidCallback onDelete) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: _textField('命令名', command.nameController)),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 16),
                onPressed: onDelete,
              ),
            ],
          ),
          for (var i = 0; i < command.params.length; i++)
            Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _textField('参数名', command.params[i].nameController),
                    ),
                    const SizedBox(width: 8),
                    _typeDropdown(
                      command.params[i].type,
                      (type) => setState(() => command.params[i].type = type),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 14),
                      onPressed: () => setState(() {
                        command.params[i].dispose();
                        command.params.removeAt(i);
                      }),
                    ),
                  ],
                ),
                if (command.params[i].type != ValueType.boolType &&
                    command.params[i].type != ValueType.string)
                  _rangeFields(command.params[i].minController,
                      command.params[i].maxController),
              ],
            ),
          TextButton.icon(
            onPressed: () =>
                setState(() => command.params.add(_ParamField(name: 'param'))),
            icon: const Icon(Icons.add, size: 14),
            label: const Text('添加参数'),
          ),
          const Divider(height: 16),
        ],
      );
}
