import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:myhome/ble/ble_constants.dart';
import 'package:myhome/ble/ble_peripheral.dart';
import 'package:myhome/ble/reactive_ble_transport.dart';

import 'fake_ble_peripheral.dart';

void main() {
  late FakeBlePeripheral peripheral;
  late ReactiveBleTransport transport;

  setUp(() {
    peripheral = FakeBlePeripheral();
    transport = ReactiveBleTransport(
      peripheral: peripheral,
      connectTimeout: const Duration(seconds: 2),
    );
  });

  tearDown(() => transport.dispose());

  test('连接成功后状态与 MTU 协商结果正确 (WORK_V2 §6.4)', () async {
    peripheral.negotiatedMtu = 185;
    await transport.connect('dev-1');

    expect(transport.isConnected, isTrue);
    expect(transport.mtu, 185); // 以实际协商结果为准，而非请求值 247
    expect(transport.connectionState, BleConnectionState.connected);
  });

  test('MTU 请求被拒绝时回退到保守值 23', () async {
    peripheral.rejectMtu = true;
    await transport.connect('dev-1');

    expect(transport.mtu, ReactiveBleTransport.fallbackMtu);
  });

  test('设备缺少目标服务时连接失败并清理状态', () async {
    peripheral.services = <String>{'0000aaaa-0000-1000-8000-00805f9b34fb'};

    await expectLater(
      transport.connect('dev-1'),
      throwsA(isA<StateError>()),
    );
    expect(transport.isConnected, isFalse);
    expect(peripheral.connectionSubscribed, isFalse); // 连接流订阅已清理
  });

  test('设备缺少目标特征时连接失败', () async {
    // 注：当前 txUuid == rxUuid (HM-10 风格共用特征)，
    // "缺特征" 用空集合表达；若后续 tx/rx 分离可单独移除其一。
    peripheral.characteristics = <String>{};

    await expectLater(transport.connect('dev-1'), throwsA(isA<StateError>()));
    expect(transport.isConnected, isFalse);
  });

  test('连接超时抛出 TimeoutException', () async {
    peripheral.autoConnect = false;

    await expectLater(
      transport.connect('dev-1'),
      throwsA(isA<TimeoutException>()),
    );
    expect(transport.isConnected, isFalse);
  });

  test('write 将字节写入 TX 特征', () async {
    await transport.connect('dev-1');
    await transport.write(<int>[0x01, 0x02, 0x03]);

    expect(peripheral.writes, hasLength(1));
    final (deviceId, serviceUuid, charUuid, value) = peripheral.writes.single;
    expect(deviceId, 'dev-1');
    expect(serviceUuid, BleConstants.serviceUuid);
    expect(charUuid, BleConstants.txUuid);
    expect(value, <int>[0x01, 0x02, 0x03]);
  });

  test('notifications 转发设备 RX Notify 数据', () async {
    await transport.connect('dev-1');
    final received = <List<int>>[];
    final sub = transport.notifications.listen(received.add);

    peripheral.emitNotification(<int>[0xaa, 0xbb]);
    await Future<void>.delayed(Duration.zero);

    expect(received, <List<int>>[
      <int>[0xaa, 0xbb],
    ]);
    await sub.cancel();
  });

  test('未连接时 write / requestMtu 抛出 StateError', () async {
    await expectLater(transport.write(<int>[1]), throwsStateError);
    await expectLater(transport.requestMtu(247), throwsStateError);
  });

  test('重复 connect 抛出 StateError', () async {
    await transport.connect('dev-1');
    await expectLater(transport.connect('dev-1'), throwsStateError);
  });

  test('disconnect 取消连接流订阅 (FRB 语义) 并更新状态', () async {
    await transport.connect('dev-1');
    await transport.disconnect();

    expect(transport.isConnected, isFalse);
    expect(peripheral.connectionSubscribed, isFalse);
  });

  test('设备侧主动断开被感知并广播状态', () async {
    await transport.connect('dev-1');
    final states = <BleConnectionState>[];
    final sub = transport.connectionStates.listen(states.add);

    peripheral.emitDisconnected();
    await Future<void>.delayed(Duration.zero);

    expect(transport.isConnected, isFalse);
    expect(states.last, BleConnectionState.disconnected);
    await sub.cancel();
  });

  test('echo 回环：写入的字节原样经 Notify 返回 (双向通信)', () async {
    peripheral.echoOnWrite = true;
    await transport.connect('dev-1');

    final echoed = Completer<List<int>>();
    final sub = transport.notifications.listen(echoed.complete);
    await transport.write(<int>[1, 2, 3, 4, 5]);

    expect(await echoed.future, <int>[1, 2, 3, 4, 5]);
    await sub.cancel();
  });
}
