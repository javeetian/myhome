import 'package:flutter_test/flutter_test.dart';

import 'package:myhome/device/defined_virtual_device.dart';
import 'package:myhome/device/device_client.dart';
import 'package:myhome/device/device_definition.dart';

void main() {
  Future<void> waitFor(
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('等待条件超时');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test('DefinedVirtualDevice 全链路：命令 → 状态推送', () async {
    final def = DeviceDefinition.fromYaml('''
device:
  id: light_bar
  name: Light Bar
  model: B100

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
  - name: light.set_brightness
    params:
      value:
        type: uint8
        min: 0
        max: 100

events:
  - name: light_bar.state_changed
''');
    final device = DefinedVirtualDevice(def);
    final client = DeviceClient(transport: device, deviceId: 'light_bar');
    addTearDown(() async {
      await client.dispose();
      await device.dispose();
    });

    await client.connect();
    await client.hello();
    await client.syncState();
    // 初始状态
    expect(client.currentState?.state['power'], isFalse);
    expect(client.currentState?.state['brightness'], 0);

    // 命令 → 状态推送
    final response = await client.command(
        'light.set_brightness', <String, dynamic>{'value': 50});
    expect(response.isOk, isTrue, reason: '${response.error?.message}');
    await waitFor(() => client.currentState?.state['brightness'] == 50);
    // 版本递增
    expect(client.currentState!.version, greaterThan(1));
  });

  test('set_power：bool 状态更新 (含 false 值)', () async {
    final def = DeviceDefinition.fromYaml('''
device:
  id: light_bar
  name: Light Bar
  model: B100
protocol:
  version: 1
api:
  version: 1
state:
  power:
    type: bool
commands:
  - name: light.set_power
    params:
      power:
        type: bool
events: []
''');
    final device = DefinedVirtualDevice(def);
    final client = DeviceClient(transport: device, deviceId: 'light_bar');
    addTearDown(() async {
      await client.dispose();
      await device.dispose();
    });
    await client.connect();
    await client.hello();
    await client.syncState();
    expect(client.currentState?.state['power'], isFalse);

    await client.command('light.set_power', <String, dynamic>{'power': true});
    await waitFor(() => client.currentState?.state['power'] == true);
    await client.command('light.set_power', <String, dynamic>{'power': false});
    await waitFor(() => client.currentState?.state['power'] == false);
  });
}