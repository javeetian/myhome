import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'fake_ble_transport.dart';

/// WORK_V2 §6.5 双向通信验证：
///   1 / 10 / 100 / 200 / 500 / 1000 字节 Write → Device → Notify → Flutter
/// 完整收发。这里用 [FakeBleTransport] 回环替代真实设备；
/// 真机验证需 ESP32/AC7014 硬件 (WORK_V2 §30)。
void main() {
  test('echo 大小矩阵：各尺寸字节完整往返', () async {
    final transport = FakeBleTransport();
    await transport.connect('echo-device');

    for (final size in <int>[1, 10, 100, 200, 500, 1000]) {
      final payload = _randomBytes(size);
      final echoed = transport.notifications.first;

      await transport.write(payload);
      final result = await echoed.timeout(const Duration(seconds: 2));

      expect(result.length, size, reason: 'size=$size 长度不符');
      expect(result, payload, reason: 'size=$size 内容不符 (字节级完整往返)');
    }

    await transport.dispose();
  });

  test('超过单次写入上限 (MTU) 的数据在回环中保持一致', () async {
    final transport = FakeBleTransport();
    await transport.connect('echo-device');
    // 模拟协商到最大 MTU
    await transport.requestMtu(247);

    final payload = _randomBytes(5000);
    final echoed = transport.notifications.first;
    await transport.write(payload);
    final result = await echoed.timeout(const Duration(seconds: 2));

    expect(result, payload);
    await transport.dispose();
  });
}

final Random _random = Random(42);

List<int> _randomBytes(int length) {
  final bytes = Uint8List(length);
  for (var i = 0; i < length; i++) {
    bytes[i] = _random.nextInt(256);
  }
  return bytes;
}
