import 'dart:async';

import 'package:myhome/ble/ble_constants.dart';
import 'package:myhome/ble/ble_peripheral.dart';

/// 可脚本化的假外设：单测注入 [ReactiveBleTransport] 以脱离真实 BLE。
class FakeBlePeripheral implements BlePeripheral {
  /// connect 后是否自动发出 connected 事件。
  bool autoConnect = true;

  /// requestMtu 返回的协商值。
  int negotiatedMtu = 185;

  /// requestMtu 是否抛异常 (模拟设备拒绝 MTU 请求)。
  bool rejectMtu = false;

  /// 已发现的服务 UUID 集合。
  Set<String> services = <String>{BleConstants.serviceUuid};

  /// 目标服务下的特征 UUID 集合。
  /// tx 与 rx 可能同用一特征 (HM-10 风格)，set 去重。
  Set<String> characteristics = <String>{
    BleConstants.txUuid,
    if (BleConstants.rxUuid != BleConstants.txUuid) BleConstants.rxUuid,
  };

  /// write 时是否将字节回环到 Notify (模拟设备 echo)。
  bool echoOnWrite = false;

  final StreamController<BleConnectionState> _connCtrl =
      StreamController<BleConnectionState>.broadcast();
  final StreamController<List<int>> _notifyCtrl =
      StreamController<List<int>>.broadcast();

  /// 记录所有 write 调用：(deviceId, serviceUuid, charUuid, value)。
  final List<(String, String, String, List<int>)> writes = <(String, String, String, List<int>)>[];

  /// 当前连接流订阅数 (FRB 语义：取消订阅 = 断开)。
  bool get connectionSubscribed => _connCtrl.hasListener;

  /// 模拟设备侧主动断开。
  void emitDisconnected() => _connCtrl.add(BleConnectionState.disconnected);

  /// 模拟设备通过 RX Notify 发来数据。
  void emitNotification(List<int> data) => _notifyCtrl.add(data);

  @override
  Stream<BleConnectionState> connect(String deviceId, {Duration? timeout}) {
    if (autoConnect) {
      scheduleMicrotask(() => _connCtrl.add(BleConnectionState.connected));
    }
    return _connCtrl.stream;
  }

  @override
  Future<void> discoverServices(String deviceId) async {}

  @override
  Future<Set<String>> serviceUuids(String deviceId) async => services;

  @override
  Future<Set<String>> characteristicUuids(
    String deviceId,
    String serviceUuid,
  ) async =>
      characteristics;

  @override
  Future<int> requestMtu(String deviceId, int mtu) async {
    if (rejectMtu) {
      throw StateError('MTU request rejected');
    }
    return negotiatedMtu;
  }

  @override
  Stream<List<int>> subscribe(
    String deviceId,
    String serviceUuid,
    String charUuid,
  ) =>
      _notifyCtrl.stream;

  @override
  Future<void> write(
    String deviceId,
    String serviceUuid,
    String charUuid,
    List<int> value,
  ) async {
    writes.add((deviceId, serviceUuid, charUuid, List<int>.of(value)));
    if (echoOnWrite) {
      _notifyCtrl.add(List<int>.of(value));
    }
  }
}
