import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:myhome/device/device_client.dart';
import 'package:myhome/protocol/protocol_messages.dart';

import 'fake_ble_device.dart';

void main() {
  late FakeBleDevice device;
  late DeviceClient client;

  setUp(() async {
    device = FakeBleDevice();
    client = DeviceClient(transport: device, deviceId: 'dev-1');
    await client.connect();
  });

  tearDown(() async {
    await client.dispose();
    await device.dispose();
  });

  group('Command / Response (§11.4)', () {
    test('command 返回设备业务响应 (request_id 配对)', () async {
      final response = await client.command('ping', const <String, dynamic>{});

      expect(response.isOk, isTrue);
      expect(response.requestId, 1);
      expect(device.receivedCommands, hasLength(1));
      expect(device.receivedCommands.single.cmd, 'ping');
    });

    test('request_id 自增', () async {
      final r1 = await client.command('a', const {});
      final r2 = await client.command('b', const {});

      expect(r1.requestId, 1);
      expect(r2.requestId, 2);
    });

    test('设备返回业务错误 (status=error) 作为正常返回值', () async {
      device.onCommand = (command) => DeviceResponse(
            requestId: command.requestId,
            status: 'error',
            error: const DeviceError(
              code: ProtocolErrorCodes.invalidParameter,
              message: 'Invalid parameter',
            ),
          );

      final response = await client.command('light.set', <String, dynamic>{'brightness': 999});

      expect(response.isOk, isFalse);
      expect(response.error?.code, 3001);
      expect(response.error?.message, 'Invalid parameter');
    });

    test('设备 ACK 但不回业务响应 → TimeoutException', () async {
      device.onCommand = (_) => null; // 不回复
      client = DeviceClient(
        transport: device,
        deviceId: 'dev-1',
        commandTimeout: const Duration(milliseconds: 100),
      );
      await client.connect();

      await expectLater(
        client.command('x', const <String, dynamic>{}),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('传输层 ACK 超时 (丢消息) → 异常传播', () async {
      device.dropMessages = 5;
      client = DeviceClient(
        transport: device,
        deviceId: 'dev-1',
        maxRetry: 1,
        ackTimeout: const Duration(milliseconds: 50),
      );
      await client.connect();

      await expectLater(
        client.command('x', const <String, dynamic>{}),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('未知 request_id 的响应被忽略', () async {
      // 设备先回一个错 request_id 的响应，再回正确响应
      device.onCommand = (command) {
        if (command.requestId == 1) {
          return DeviceResponse(requestId: 999, data: const <String, dynamic>{'wrong': true});
        }
        return null;
      };

      // 第一条会因 request_id 不匹配而超时
      client = DeviceClient(
        transport: device,
        deviceId: 'dev-1',
        commandTimeout: const Duration(milliseconds: 80),
      );
      await client.connect();
      await expectLater(
        client.command('x', const {}),
        throwsA(isA<TimeoutException>()),
      );

      // 恢复正确配对后正常
      device.onCommand = (command) => DeviceResponse(requestId: command.requestId);
      final response = await client.command('y', const <String, dynamic>{});
      expect(response.requestId, 2);
    });
  });

  group('Event / Patch / State (§11.4)', () {
    test('events 流收到设备事件', () async {
      final received = client.events.first;
      device.sendEvent('temperature.changed', <String, dynamic>{'value': 25.5});

      final event = await received.timeout(const Duration(seconds: 2));
      expect(event.event, 'temperature.changed');
      expect(event.data['value'], 25.5);
    });

    test('patches 流收到状态补丁', () async {
      final received = client.patches.first;
      device.sendPatch(103, <Map<String, dynamic>>[
        <String, dynamic>{'op': 'replace', 'path': '/brightness', 'value': 60},
      ]);

      final patch = await received.timeout(const Duration(seconds: 2));
      expect(patch.version, 103);
      expect(patch.ops.single['path'], '/brightness');
    });

    test('getState 返回缓存的设备状态', () async {
      final received = client.states.first;
      device.sendState(100, <String, dynamic>{'power': true});

      await received.timeout(const Duration(seconds: 2));
      final state = await client.getState();
      expect(state.version, 100);
      expect(state.state['power'], isTrue);
    });

    test('未收到状态时 getState 抛 StateError', () async {
      await expectLater(client.getState(), throwsA(isA<StateError>()));
    });
  });

  group('连接状态与边界', () {
    test('未连接时 command 抛 StateError', () async {
      final offline = DeviceClient(transport: device, deviceId: 'dev-1');

      await expectLater(
        offline.command('x', const <String, dynamic>{}),
        throwsA(isA<StateError>()),
      );
      await offline.dispose();
    });

    test('disconnect 失败所有进行中的命令', () async {
      device.onCommand = (_) => null; // 不回复，让命令挂起
      final pending = client.command('x', const <String, dynamic>{});
      // 先挂监听再触发错误，否则错误成为 unhandled async error
      final expectation = expectLater(pending, throwsA(isA<StateError>()));

      await Future<void>.delayed(const Duration(milliseconds: 30));
      await client.disconnect();

      await expectation;
    });
  });
}
