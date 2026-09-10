import 'dart:typed_data';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:myhome/ble/ble_scanner.dart';

/// 构造测试用扫描结果 (可指定广播服务 UUID 列表)。
DiscoveredDevice device({
  List<String> serviceUuids = const <String>[],
  List<String> serviceDataUuids = const <String>[],
}) =>
    DiscoveredDevice(
      id: 'dev-1',
      name: 'Light',
      serviceUuids: serviceUuids.map(Uuid.parse).toList(),
      serviceData: <Uuid, Uint8List>{
        for (final uuid in serviceDataUuids) Uuid.parse(uuid): Uint8List(0),
      },
      manufacturerData: Uint8List(0),
      rssi: -50,
    );

/// 扫描过滤 (WORK_V2 §6.3)：只保留广播 BleConstants.serviceUuid 的设备。
void main() {
  test('广播 128 位服务 UUID 命中', () {
    expect(
      BleScanner.matchesTarget(device(serviceUuids: <String>[
        '0000ffe0-0000-1000-8000-00805f9b34fb',
      ])),
      isTrue,
    );
  });

  test('16 位短 UUID (0xFFE0) 等价命中', () {
    expect(
      BleScanner.matchesTarget(device(serviceUuids: <String>['ffe0'])),
      isTrue,
    );
  });

  test('32 位短 UUID 等价命中', () {
    expect(
      BleScanner.matchesTarget(device(serviceUuids: <String>['0000ffe0'])),
      isTrue,
    );
  });

  test('serviceData 中的 UUID 命中', () {
    expect(
      BleScanner.matchesTarget(device(serviceDataUuids: <String>['ffe0'])),
      isTrue,
    );
  });

  test('无关设备被过滤', () {
    expect(
      BleScanner.matchesTarget(device(serviceUuids: <String>[
        '0000180f-0000-1000-8000-00805f9b34fb', // 标准电池服务
      ])),
      isFalse,
    );
    expect(BleScanner.matchesTarget(device()), isFalse);
  });
}
