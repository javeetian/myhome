import 'package:flutter_test/flutter_test.dart';

import 'package:myhome/device/device_client.dart';

import '../protocol/fake_ble_device.dart';

/// 心跳 PING/PONG (Phase 12 §22 扩展) 测试。
void main() {
  late FakeBleDevice device;
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
    device = FakeBleDevice();
    client = DeviceClient(transport: device, deviceId: 'dev-1');
    await client.connect();
  });

  tearDown(() async {
    await client.dispose();
    await device.dispose();
  });

  test('心跳：PING → PONG 往返，失联回调不触发', () async {
    var lost = 0;
    client.onConnectionLost = () => lost++;
    client.startHeartbeat(
      interval: const Duration(milliseconds: 50),
      missedThreshold: 3,
    );

    await waitFor(() => device.receivedPings.length >= 2);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(lost, 0, reason: '设备正常回 PONG，不应判定失联');
  });

  test('失联：连续无 PONG → onConnectionLost (§20)', () async {
    device.onPing = (_) => null; // 设备不回 PONG
    var lost = 0;
    client.onConnectionLost = () => lost++;
    client.startHeartbeat(
      interval: const Duration(milliseconds: 50),
      missedThreshold: 3,
    );

    await waitFor(() => lost > 0);
    expect(lost, 1, reason: '失联回调只触发一次');
  });

  test('stopHeartbeat 停止心跳', () async {
    client.startHeartbeat(
      interval: const Duration(milliseconds: 30),
      missedThreshold: 3,
    );
    await waitFor(() => device.receivedPings.isNotEmpty);
    client.stopHeartbeat();
    final count = device.receivedPings.length;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(device.receivedPings.length, count, reason: '停止后不再发 PING');
  });

  test('dispose 释放心跳定时器', () async {
    client.startHeartbeat(interval: const Duration(milliseconds: 30));
    await waitFor(() => device.receivedPings.isNotEmpty);
    await client.dispose(); // 若定时器未取消，测试会因 pending timer 失败
  });
}
