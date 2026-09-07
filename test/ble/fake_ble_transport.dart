import 'dart:async';

import 'package:myhome/ble/ble_transport.dart';

/// 回环假传输：写入的字节原样从 notifications 返回 (模拟设备 echo)。
/// 用于脱离真实硬件的双向通信验证 (WORK_V2 §6.5) 及后续各层单测
/// (WORK_V2 §11.4 MockBleTransport)。
class FakeBleTransport implements BleTransport {
  final StreamController<List<int>> _notifications =
      StreamController<List<int>>.broadcast();

  bool _connected = false;
  int _mtu = 23;

  /// 当前协商 MTU。
  int get mtu => _mtu;

  bool get isConnected => _connected;

  /// 写入字节数统计。
  int writeCount = 0;

  @override
  Future<void> connect(String deviceId) async {
    _connected = true;
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
  }

  @override
  Future<void> write(List<int> data) async {
    if (!_connected) {
      throw StateError('未连接，无法写入');
    }
    writeCount++;
    final echo = List<int>.of(data);
    scheduleMicrotask(() => _notifications.add(echo));
  }

  @override
  Stream<List<int>> get notifications => _notifications.stream;

  @override
  Future<int> requestMtu(int mtu) async {
    if (!_connected) {
      throw StateError('未连接，无法协商 MTU');
    }
    _mtu = mtu.clamp(23, 247);
    return _mtu;
  }

  /// 释放资源。
  Future<void> dispose() async {
    await _notifications.close();
  }
}
