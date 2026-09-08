import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:myhome/device/device_client.dart';
import 'package:myhome/simulator/fault_injector.dart';

import '../protocol/fake_ble_device.dart';

/// 压力测试 (WORK_V3 §34)：Payload 大小矩阵 × 丢包率矩阵。
/// 验证分片 + 重试在恶劣链路下的完整性与吞吐表现。
void main() {
  const sizes = <String, int>{'100B': 100, '1KB': 1000, '10KB': 10000};
  const lossRates = <String, double>{'0%': 0, '5%': 0.05, '10%': 0.10};

  for (final sizeEntry in sizes.entries) {
    for (final lossEntry in lossRates.entries) {
      test('${sizeEntry.key} @ 丢包 ${lossEntry.key} → 完整性 + 吞吐', () async {
        final device = FakeBleDevice();
        final injector = FaultInjector(device)..txPacketLoss = lossEntry.value;
        final client = DeviceClient(
          transport: injector,
          deviceId: 'dev-1',
          ackTimeout: const Duration(milliseconds: 200),
          commandTimeout: const Duration(seconds: 60),
        );
        addTearDown(() async {
          await client.dispose();
          await injector.dispose();
          await device.dispose();
        });
        await client.connect();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final payload = Uint8List.fromList(
          List<int>.filled(sizeEntry.value, 0xAB),
        );
        final encoded = base64Encode(payload);
        final stopwatch = Stopwatch()..start();
        final response = await client.command(
          'echo',
          <String, dynamic>{'data': encoded},
        );
        stopwatch.stop();

        expect(response.isOk, isTrue);
        // 设备回显一致 (分片完整性)
        final echo = (response.data?['echo'] as Map<String, dynamic>)['data'];
        expect(echo, encoded, reason: '回显数据逐字节一致');
        expect(base64Decode(echo as String), payload);

        // 吞吐基线 (仅记录，供真机对照 §28)
        final throughputKbps = client.stats.txBytes * 8 / 1000 /
            (stopwatch.elapsedMilliseconds / 1000);
        // ignore: avoid_print
        print('RESULT ${sizeEntry.key} @loss${lossEntry.key}: '
            '${stopwatch.elapsedMilliseconds}ms '
            'tx=${client.stats.txBytes}B retries=${client.stats.retries} '
            'throughput=${throughputKbps.toStringAsFixed(1)}kbps');
      }, timeout: const Timeout(Duration(minutes: 3)));
    }
  }
}
