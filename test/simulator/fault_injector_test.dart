import 'package:flutter_test/flutter_test.dart';

import 'package:myhome/device/device_client.dart';
import 'package:myhome/simulator/fault_injector.dart';

import '../protocol/fake_ble_device.dart';

/// 故障注入器 (WORK_V3 §32) 测试：
/// 经 DeviceClient 全链路验证各故障的协议层恢复行为。
void main() {
  late FakeBleDevice device;
  late FaultInjector injector;
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
    injector = FaultInjector(device);
    client = DeviceClient(transport: injector, deviceId: 'dev-1');
    await client.connect();
    await waitFor(() => client.hasState);
  });

  tearDown(() async {
    await client.dispose();
    await injector.dispose();
    await device.dispose();
  });

  test('无故障：命令正常往返', () async {
    final response = await client.command('ping', const <String, dynamic>{});
    expect(response.isOk, isTrue);
  });

  test('丢包 100% → 重试耗尽 → 命令抛异常', () async {
    injector.txPacketLoss = 1.0;
    await expectLater(
      client.command('ping', const <String, dynamic>{}),
      throwsA(anything),
    );
    expect(injector.injectedLoss, greaterThan(0));
  });

  test('延迟 100ms → 命令成功且更慢', () async {
    injector.txDelay = const Duration(milliseconds: 100);
    final stopwatch = Stopwatch()..start();
    final response = await client.command('ping', const <String, dynamic>{});
    stopwatch.stop();
    expect(response.isOk, isTrue);
    expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(90));
  });

  test('CRC 损坏 100% → 每次重发均损坏 → 重试耗尽失败', () async {
    injector.txCrcErrorRate = 1.0;
    await expectLater(
      client.command('ping', const <String, dynamic>{}),
      throwsA(anything),
    );
    expect(injector.injectedCrcError, greaterThan(0));
    expect(client.stats.retries, 3, reason: 'maxRetry 耗尽');
  });

  test('重复 100% → 设备按 SEQ 去重 → 命令成功一次', () async {
    injector.txDuplicateRate = 1.0;
    final response = await client.command('ping', const <String, dynamic>{});
    expect(response.isOk, isTrue);
    expect(device.receivedCommands.length, 1, reason: '重复帧被去重');
  });

  test('注入断开：下次写入失败 + 回调触发', () async {
    var disconnected = 0;
    injector.onDisconnectRequested = () => disconnected++;
    injector.disconnectOnNextWrite = true;

    await expectLater(
      client.command('ping', const <String, dynamic>{}),
      throwsA(anything),
    );
    expect(disconnected, 1);
  });
}
