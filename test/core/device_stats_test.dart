import 'package:flutter_test/flutter_test.dart';

import 'package:myhome/core/device_stats.dart';

/// 通信统计 (WORK_V2 §28/§33) 测试。
void main() {
  test('TX/RX 字节与重试计数', () {
    final stats = DeviceStats();
    stats.addTx(100);
    stats.addTx(50);
    stats.addRx(80);
    stats.addRetry();
    stats.addRetry();

    expect(stats.txBytes, 150);
    expect(stats.rxBytes, 80);
    expect(stats.retries, 2);
  });

  test('命令延迟分位数 P50/P95/P99 (§28.3)', () {
    final stats = DeviceStats();
    for (final ms in <int>[10, 20, 30, 40, 50, 60, 70, 80, 90, 100]) {
      stats.recordCommandLatency(Duration(milliseconds: ms));
    }

    expect(stats.commandCount, 10);
    expect(stats.commandLatencyP50, 60); // 10 个样本，50% → 第 5 个 (0 基) = 60
    expect(stats.commandLatencyP95, 100);
    expect(stats.commandLatencyP99, 100);
  });

  test('无样本时分位数为 null', () {
    final stats = DeviceStats();
    expect(stats.commandLatencyP50, isNull);
    expect(stats.commandLatencyP95, isNull);
    expect(stats.commandLatencyP99, isNull);
    expect(stats.commandCount, 0);
  });

  test('连接时间记录', () {
    final stats = DeviceStats();
    expect(stats.connectedAt, isNull);
    stats.markConnected();
    expect(stats.connectedAt, isNotNull);
  });
}
