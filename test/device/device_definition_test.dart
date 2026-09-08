import 'package:flutter_test/flutter_test.dart';

import 'package:myhome/device/device_definition.dart';

/// Device Definition (WORK_V3 Phase 1/2) 测试。
void main() {
  const validYaml = '''
device:
  id: smart_light
  name: Smart Light
  model: L100

protocol:
  version: 1

api:
  version: 1

state:
  power:
    type: bool
  brightness:
    type: uint8
    min: 0
    max: 100

commands:
  - name: light.set_power
    params:
      power:
        type: bool

events:
  - name: light.state_changed
''';

  group('Phase 1 解析', () {
    test('完整 device.yaml → DeviceDefinition (§6 示例)', () {
      final def = DeviceDefinition.fromYaml(validYaml);

      expect(def.id, 'smart_light');
      expect(def.name, 'Smart Light');
      expect(def.model, 'L100');
      expect(def.protocolVersion, 1);
      expect(def.apiVersion, 1);
      expect(def.state['power']?.type, ValueType.boolType);
      expect(def.state['brightness']?.type, ValueType.uint8);
      expect(def.state['brightness']?.min, 0);
      expect(def.state['brightness']?.max, 100);
      expect(def.commands.single.name, 'light.set_power');
      expect(def.commands.single.params['power']?.type, ValueType.boolType);
      expect(def.events.single.name, 'light.state_changed');
    });

    test('最小定义 (仅 device.id + 版本)', () {
      final def = DeviceDefinition.fromYaml('''
device:
  id: minimal
protocol:
  version: 1
api:
  version: 1
''');
      expect(def.id, 'minimal');
      expect(def.name, '');
      expect(def.state, isEmpty);
      expect(def.commands, isEmpty);
    });
  });

  group('Phase 2 校验 (错误矩阵)', () {
    void expectErrors(String yaml, List<String> expectedErrors) {
      try {
        DeviceDefinition.fromYaml(yaml);
        fail('应当抛出 DeviceDefinitionException');
      } on DeviceDefinitionException catch (e) {
        for (final expected in expectedErrors) {
          expect(
            e.errors.any((error) => error.contains(expected)),
            isTrue,
            reason: '缺少错误 "$expected"，实际: ${e.errors}',
          );
        }
      }
    }

    test('missing device.id', () {
      expectErrors('''
device:
  name: X
protocol:
  version: 1
api:
  version: 1
''', <String>['missing device.id']);
    });

    test('missing protocol.version', () {
      expectErrors('''
device:
  id: x
api:
  version: 1
''', <String>['missing protocol.version']);
    });

    test('invalid state type (unsupported type)', () {
      expectErrors('''
device:
  id: x
protocol:
  version: 1
api:
  version: 1
state:
  foo:
    type: fancy
''', <String>['invalid state "foo"', 'unsupported type "fancy"']);
    });

    test('invalid command parameter (params 不是 map)', () {
      expectErrors('''
device:
  id: x
protocol:
  version: 1
api:
  version: 1
commands:
  - name: cmd.a
    params: nope
''', <String>['invalid command "cmd.a"', 'params 必须是 map']);
    });

    test('duplicate command', () {
      expectErrors('''
device:
  id: x
protocol:
  version: 1
api:
  version: 1
commands:
  - name: cmd.a
  - name: cmd.a
''', <String>['duplicate command "cmd.a"']);
    });

    test('invalid command parameter type', () {
      expectErrors('''
device:
  id: x
protocol:
  version: 1
api:
  version: 1
commands:
  - name: cmd.a
    params:
      value:
        type: int64
''', <String>['invalid parameter "value"', 'unsupported type "int64"']);
    });

    test('min > max', () {
      expectErrors('''
device:
  id: x
protocol:
  version: 1
api:
  version: 1
state:
  brightness:
    type: uint8
    min: 100
    max: 0
''', <String>['min (100) 不能大于 max (0)']);
    });

    test('YAML 语法错误', () {
      expectErrors('device: [broken', <String>['YAML 语法错误']);
    });

    test('多个错误一次性收集', () {
      try {
        DeviceDefinition.fromYaml('''
device:
  name: X
commands:
  - name: a
  - name: a
''');
        fail('应当抛出');
      } on DeviceDefinitionException catch (e) {
        expect(e.errors.length, greaterThanOrEqualTo(3)); // id/version×2/duplicate
      }
    });
  });
}
