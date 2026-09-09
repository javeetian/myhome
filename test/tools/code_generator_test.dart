import 'package:flutter_test/flutter_test.dart';

import 'package:myhome/device/device_definition.dart';
import 'package:myhome/tools/code_generator.dart';

/// Code Generator (WORK_V3 §41-§45) 测试。
void main() {
  late DeviceDefinition def;

  setUp(() {
    def = DeviceDefinition.fromYaml('''
device:
  id: smart_light
  name: Smart Light
  model: L100

protocol:
  version: 1

api:
  version: 2

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
  - name: light.set_brightness
    params:
      value:
        type: uint8
        min: 0
        max: 100

events:
  - name: light.state_changed
''');
  });

  test('生成产物齐全 (§41 七件套)', () {
    final files = CodeGenerator.generate(def);
    expect(files.keys.toSet(), <String>{
      'c/device_api.h',
      'c/device_api.c',
      'c/device_commands.c',
      'c/device_state.h',
      'dart/device_api.dart',
      'simulator/virtual_device.dart',
      'manifest.json',
    });
  });

  test('C 头文件：命令原型 + 类型映射', () {
    final header = CodeGenerator.generate(def)['c/device_api.h']!;
    expect(header, contains('int light_set_power('));
    expect(header, contains('bool power'));
    expect(header, contains('int light_set_brightness('));
    expect(header, contains('uint8_t value'));
    expect(header, contains('#ifndef DEVICE_API_H'));
  });

  test('C 命令路由：命令表 (device_commands.c)', () {
    final commands = CodeGenerator.generate(def)['c/device_commands.c']!;
    expect(commands, contains('{ "light.set_power"'));
    expect(commands, contains('{ "light.set_brightness"'));
    expect(commands, contains('g_command_count'));
  });

  test('C 命令处理：参数解析校验 → 调用开发者函数 (device_api.c)', () {
    final api = CodeGenerator.generate(def)['c/device_api.c']!;
    expect(api, contains('device_handle_command'));
    expect(api, contains('ERR_UNKNOWN_COMMAND'));
    expect(api, contains('device_json_get_uint(params_json, "value"'));
    expect(api, contains('越界 [0, 100]'));
    expect(api, contains('light_set_brightness(value, response_json, response_len)'));
    expect(api, contains('light_set_power(power, response_json, response_len)'));
  });

  test('C 状态结构体', () {
    final state = CodeGenerator.generate(def)['c/device_state.h']!;
    expect(state, contains('uint32_t version;'));
    expect(state, contains('bool power;'));
    expect(state, contains('uint8_t brightness;'));
  });

  test('Dart API：强类型方法 + 状态模型', () {
    final dart = CodeGenerator.generate(def)['dart/device_api.dart']!;
    expect(dart, contains('class SmartLightApi'));
    expect(dart, contains('Future<DeviceResponse> lightSetPower({required bool power})'));
    expect(dart, contains("_client.command('light.set_power'"));
    expect(dart, contains('class SmartLightState'));
    expect(dart, contains("(json['brightness'] as num).toInt()"));
  });

  test('Simulator 骨架：协议接线 + 参数校验 + TODO 业务点', () {
    final sim = CodeGenerator.generate(def)['simulator/virtual_device.dart']!;
    expect(sim, contains('class SmartLightVirtualDevice extends ProtocolDevice'));
    expect(sim, contains("deviceId => 'smart_light'"));
    expect(sim, contains("case 'light.set_power':"));
    expect(sim, contains('TODO: 业务逻辑'));
    expect(sim, contains('capabilities'));
  });

  test('manifest.json：V3 格式 + capabilities 来自状态键', () {
    final manifest = CodeGenerator.generate(def)['manifest.json']!;
    expect(manifest, contains('"protocol": {'));
    expect(manifest, contains('"version": 1'));
    expect(manifest, contains('"api_version": 2'));
    expect(manifest, contains('"power"'));
    expect(manifest, contains('"brightness"'));
    expect(manifest, contains('"type": "smart_light"'));
  });
}
