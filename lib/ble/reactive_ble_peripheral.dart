import 'dart:async';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import 'ble_peripheral.dart';

/// [BlePeripheral] 的 flutter_reactive_ble 适配器：
/// 把窄接口映射到 FRB 的 QualifiedCharacteristic / DiscoveredService API。
class ReactiveBlePeripheral implements BlePeripheral, ConnectionPriorityControl {
  ReactiveBlePeripheral(this._ble);

  final FlutterReactiveBle _ble;

  QualifiedCharacteristic _char(
    String deviceId,
    String serviceUuid,
    String charUuid,
  ) =>
      QualifiedCharacteristic(
        characteristicId: Uuid.parse(charUuid),
        serviceId: Uuid.parse(serviceUuid),
        deviceId: deviceId,
      );

  @override
  Stream<BleConnectionState> connect(String deviceId, {Duration? timeout}) {
    return _ble
        .connectToDevice(id: deviceId, connectionTimeout: timeout)
        .map(_mapState)
        .distinct();
  }

  BleConnectionState _mapState(ConnectionStateUpdate update) {
    switch (update.connectionState) {
      case DeviceConnectionState.connected:
        return BleConnectionState.connected;
      case DeviceConnectionState.connecting:
        return BleConnectionState.connecting;
      case DeviceConnectionState.disconnecting:
        return BleConnectionState.disconnecting;
      case DeviceConnectionState.disconnected:
        return BleConnectionState.disconnected;
    }
  }

  @override
  Future<void> discoverServices(String deviceId) async {
    await _ble.discoverAllServices(deviceId);
  }

  @override
  Future<Set<String>> serviceUuids(String deviceId) async {
    final services = await _ble.getDiscoveredServices(deviceId);
    return services.map((s) => s.id.toString()).toSet();
  }

  @override
  Future<Set<String>> characteristicUuids(
    String deviceId,
    String serviceUuid,
  ) async {
    final services = await _ble.getDiscoveredServices(deviceId);
    for (final service in services) {
      if (service.id.toString() == serviceUuid) {
        return service.characteristics
            .map((c) => c.id.toString())
            .toSet();
      }
    }
    return <String>{};
  }

  @override
  Future<int> requestMtu(String deviceId, int mtu) {
    return _ble.requestMtu(deviceId: deviceId, mtu: mtu);
  }

  @override
  Stream<List<int>> subscribe(
    String deviceId,
    String serviceUuid,
    String charUuid,
  ) {
    return _ble.subscribeToCharacteristic(_char(deviceId, serviceUuid, charUuid));
  }

  @override
  Future<void> write(
    String deviceId,
    String serviceUuid,
    String charUuid,
    List<int> value,
  ) {
    return _ble.writeCharacteristicWithResponse(
      _char(deviceId, serviceUuid, charUuid),
      value: value,
    );
  }

  @override
  Future<void> writeWithoutResponse(
    String deviceId,
    String serviceUuid,
    String charUuid,
    List<int> value,
  ) {
    return _ble.writeCharacteristicWithoutResponse(
      _char(deviceId, serviceUuid, charUuid),
      value: value,
    );
  }

  /// 连接优先级：HIGH = 11.25ms 间隔，BALANCED = 系统默认 (通常 30–50ms)
  @override
  Future<void> requestConnectionPriority(String deviceId, {required bool high}) {
    return _ble.requestConnectionPriority(
      deviceId: deviceId,
      priority: high
          ? ConnectionPriority.highPerformance
          : ConnectionPriority.balanced,
    );
  }
}
