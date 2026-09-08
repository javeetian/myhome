import 'dart:async';
import 'dart:math';

import '../ble/ble_peripheral.dart';
import '../ble/ble_transport.dart';

/// 故障注入器 (WORK_V3 §32)：包装 [BleTransport]，按配置注入通信故障。
///
/// 故障类型：
///   Packet Loss       丢包 (双向)
///   Packet Delay      延迟
///   Duplicate         重复包
///   CRC Error         字节损坏 (接收端 CRC 校验失败丢弃)
///   Disconnect        主动断开 (设备侧断线信号)
///
/// 用途：Device Studio 故障注入面板 (Phase 21) 与异常矩阵回归 (§33)。
class FaultInjector implements BleTransport {
  FaultInjector(this.inner);

  final BleTransport inner;

  final Random _random = Random();

  /// 丢包率 [0, 1] (App → 设备)。
  double txPacketLoss = 0;

  /// 延迟 (写入前等待)。
  Duration txDelay = Duration.zero;

  /// 重复率 [0, 1] (同包写两次)。
  double txDuplicateRate = 0;

  /// CRC 损坏率 [0, 1] (翻转字节)。
  double txCrcErrorRate = 0;

  /// 下一次写入时主动断开 (模拟设备重启/掉线)。
  bool disconnectOnNextWrite = false;

  /// 设备侧断线信号 (Simulator → App)。
  void Function()? onDisconnectRequested;

  bool _connected = false;

  /// 各故障总注入次数 (Inspector 显示)。
  int injectedLoss = 0;
  int injectedDuplicate = 0;
  int injectedCrcError = 0;

  @override
  Future<void> connect(String deviceId) async {
    await inner.connect(deviceId);
    _connected = true;
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    await inner.disconnect();
  }

  @override
  Future<void> write(List<int> data) async {
    if (!_connected) {
      throw StateError('未连接，无法写入');
    }
    if (disconnectOnNextWrite) {
      disconnectOnNextWrite = false;
      _connected = false;
      await inner.disconnect();
      onDisconnectRequested?.call();
      throw StateError('故障注入：写入时断开');
    }
    // 丢包
    if (_random.nextDouble() < txPacketLoss) {
      injectedLoss++;
      return; // 静默丢弃 (上层靠 ACK 超时/重试恢复)
    }
    // 延迟
    if (txDelay > Duration.zero) {
      await Future<void>.delayed(txDelay);
    }
    // CRC 损坏
    var payload = data;
    if (_random.nextDouble() < txCrcErrorRate && data.isNotEmpty) {
      injectedCrcError++;
      payload = List<int>.of(data);
      payload[payload.length - 1] ^= 0xFF; // 翻转 CRC 尾字节
    }
    await inner.write(payload);
    // 重复
    if (_random.nextDouble() < txDuplicateRate) {
      injectedDuplicate++;
      await inner.write(data); // 原包再发一次 (接收端按 SEQ 去重)
    }
  }

  @override
  Stream<List<int>> get notifications => inner.notifications;

  @override
  Stream<BleConnectionState> get connectionStates => inner.connectionStates;

  @override
  Future<int> requestMtu(int mtu) => inner.requestMtu(mtu);

  /// 释放资源。
  Future<void> dispose() async {
    await disconnect();
  }
}
