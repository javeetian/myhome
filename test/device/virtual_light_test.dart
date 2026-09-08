import 'package:flutter_test/flutter_test.dart';

import 'package:myhome/device/device_client.dart';
import 'package:myhome/device/virtual_light.dart';

/// Smart Light 虚拟设备 (WORK_V3 §2/§7) 全链路测试：
/// DeviceClient → Protocol → SimulatorTransport → VirtualLight → VirtualHardware。
void main() {
  late VirtualLight light;
  late DeviceClient client;

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

  setUp(() async {
    light = VirtualLight();
    client = DeviceClient(transport: light, deviceId: light.deviceId);
    await client.connect();
  });

  tearDown(() async {
    await client.dispose();
    await light.dispose();
  });

  test('连接 → 初始状态推送 (§7 状态模型)', () async {
    await waitFor(() => client.hasState);
    final state = await client.getState();
    expect(state.version, 1);
    expect(state.state['power'], isFalse);
    expect(state.state['brightness'], 80);
    expect(state.state['color_temperature'], 4000);
  });

  test('HELLO 握手：能力与 UI 版本声明', () async {
    final ack = await client.hello();
    expect(ack.deviceType, 'light');
    expect(ack.deviceModel, 'L100');
    expect(ack.capabilities, contains('brightness'));
  });

  test('命令 → 响应 + 状态版本递增 + 事件 (§45 验收流程)', () async {
    await waitFor(() => client.hasState);
    final eventFuture = client.events.first;
    final response =
        await client.command('light.set_brightness', <String, dynamic>{'value': 60});

    expect(response.isOk, isTrue);
    expect(response.data?['version'], 2);

    await waitFor(() => client.currentState?.state['brightness'] == 60);
    expect(client.currentState?.version, 2);

    final event = await eventFuture.timeout(const Duration(seconds: 2));
    expect(event.event, 'light.state_changed');
    expect(event.data['version'], 2);
  });

  test('业务错误：无效参数 → status=error (正常返回)', () async {
    await waitFor(() => client.hasState);
    final response = await client.command(
        'light.set_brightness', <String, dynamic>{'value': 999});
    expect(response.status, 'error');
    expect(response.error?.code, 3001);
  });

  test('未知命令 → 3002', () async {
    await waitFor(() => client.hasState);
    final response = await client.command('light.fly', const <String, dynamic>{});
    expect(response.error?.code, 3002);
  });

  test('状态同步：getState 返回当前硬件快照', () async {
    await waitFor(() => client.hasState);
    await client.command('light.set_power', <String, dynamic>{'power': true});
    await waitFor(() => client.currentState?.state['power'] == true);
    final state = await client.getState();
    expect(state.state['power'], isTrue);
  });
}
