import 'dart:async';

/// BLE 连接状态。
enum BleConnectionState { connecting, connected, disconnecting, disconnected }

/// BLE 外设操作窄接口：Transport 实现只通过它访问具体 Plugin，
/// 单元测试注入 Fake 即可脱离真实 BLE (WORK_V2 §5.2 / §11.4)。
abstract class BlePeripheral {
  /// 连接设备，返回连接状态流 (取消订阅 = 断开连接)。
  Stream<BleConnectionState> connect(String deviceId, {Duration? timeout});

  /// 发现设备全部 GATT 服务。
  Future<void> discoverServices(String deviceId);

  /// 已发现服务的 UUID 集合。
  Future<Set<String>> serviceUuids(String deviceId);

  /// 指定服务下特征的 UUID 集合。
  Future<Set<String>> characteristicUuids(String deviceId, String serviceUuid);

  /// 请求协商 MTU，返回实际协商结果。
  Future<int> requestMtu(String deviceId, int mtu);

  /// 订阅指定特征的 Notify。
  Stream<List<int>> subscribe(
    String deviceId,
    String serviceUuid,
    String charUuid,
  );

  /// 向指定特征写入 (带响应确认)。
  Future<void> write(
    String deviceId,
    String serviceUuid,
    String charUuid,
    List<int> value,
  );
}
