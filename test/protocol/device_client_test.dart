import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:myhome/device/device_client.dart';
import 'package:myhome/protocol/protocol_messages.dart';

import 'fake_ble_device.dart';

/// 轮询等待条件成立 (状态经多层流异步传播)。
Future<void> waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('等待条件超时');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

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
      await waitFor(() => client.hasState); // 等初始状态 (§16.6)
      final received = client.patches.first;
      device.sendPatch(2, <Map<String, dynamic>>[
        <String, dynamic>{'op': 'replace', 'path': '/brightness', 'value': 60},
      ]);

      final patch = await received.timeout(const Duration(seconds: 2));
      expect(patch.version, 2);
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

    test('getState 未同步时主动请求全量 (§16.6)', () async {
      // 重新连接且不推初始状态：客户端无状态基准
      await client.disconnect();
      device.pushInitialStateOnConnect = false;
      await client.connect();

      final state = await client.getState();

      expect(device.receivedStateRequests.length, 1);
      expect(state.version, 1);
    });
  });

  group('Phase 11 状态管理 (§16)', () {
    test('Patch 应用到本地状态副本 (§16.3)', () async {
      await waitFor(() => client.hasState); // setUp 连接时已推初始状态 v1
      device.sendPatch(2, <Map<String, dynamic>>[
        <String, dynamic>{'op': 'replace', 'path': '/power', 'value': true},
      ]);
      await waitFor(() => client.currentState?.version == 2);

      final state = await client.getState();
      expect(state.version, 2);
      expect(state.state['power'], isTrue);
    });

    test('Patch 嵌套路径与 add/remove (§16.3)', () async {
      await waitFor(() => client.hasState);
      device.sendState(10, <String, dynamic>{
        'led': <String, dynamic>{'on': false},
      });
      await waitFor(() => client.currentState?.version == 10);

      device.sendPatch(11, <Map<String, dynamic>>[
        <String, dynamic>{'op': 'replace', 'path': '/led/on', 'value': true},
        <String, dynamic>{'op': 'add', 'path': '/brightness', 'value': 60},
      ]);
      await waitFor(() => client.currentState?.version == 11);
      device.sendPatch(12, <Map<String, dynamic>>[
        <String, dynamic>{'op': 'remove', 'path': '/brightness'},
      ]);
      await waitFor(() => client.currentState?.version == 12);

      final state = await client.getState();
      expect(state.version, 12);
      expect(state.state['led'], <String, dynamic>{'on': true});
      expect(state.state.containsKey('brightness'), isFalse);
    });

    test('版本跳跃 (Gap) → 自动 STATE_REQUEST 补全 (§16.5)', () async {
      await waitFor(() => client.hasState);
      device.onStateRequest = (request) => const DeviceState(
            version: 5,
            state: <String, dynamic>{'power': true, 'brightness': 80},
          );
      device.sendPatch(5, <Map<String, dynamic>>[
        <String, dynamic>{'op': 'replace', 'path': '/brightness', 'value': 60},
      ]);
      await waitFor(() => device.receivedStateRequests.length == 1);
      // 全量兜底覆盖增量结果
      await waitFor(
        () => client.currentState?.state['brightness'] == 80,
      );

      final state = await client.getState();
      expect(state.version, 5);
      expect(state.state['brightness'], 80);
    });

    test('无基准状态的 Patch → 请求全量 (§16.6)', () async {
      await client.disconnect();
      device.pushInitialStateOnConnect = false;
      await client.connect();

      device.onStateRequest = (request) => const DeviceState(
            version: 3,
            state: <String, dynamic>{'power': true},
          );
      device.sendPatch(3, <Map<String, dynamic>>[
        <String, dynamic>{'op': 'replace', 'path': '/power', 'value': true},
      ]);
      await waitFor(() => client.hasState && client.currentState?.version == 3);

      expect(device.receivedStateRequests.length, 1);
      expect((await client.getState()).state['power'], isTrue);
    });

    test('过期 Patch 忽略 (§16.5)', () async {
      await waitFor(() => client.hasState);
      device.sendState(10, <String, dynamic>{'power': true});
      await waitFor(() => client.currentState?.version == 10);

      device.sendPatch(5, <Map<String, dynamic>>[
        <String, dynamic>{'op': 'replace', 'path': '/power', 'value': false},
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final state = await client.getState();
      expect(state.version, 10);
      expect(state.state['power'], isTrue);
    });

    test('断线清空状态存储 (§21 重连必须重新同步)', () async {
      await waitFor(() => client.hasState);
      device.sendState(9, <String, dynamic>{'power': true});
      await waitFor(() => client.currentState?.version == 9);
      expect((await client.getState()).version, 9);

      await client.disconnect();
      expect(client.hasState, isFalse);
    });
  });

  group('Phase 24 Replaceable 命令队列 (§39)', () {
    test('快速连发同键命令 → 中间被替换，只发首尾', () async {
      device.ackDelay = const Duration(milliseconds: 100); // 保持 inflight
      await waitFor(() => client.hasState);

      final results = await Future.wait<Object>([
        for (var i = 1; i <= 5; i++)
          client
              .command('set_brightness',
                  <String, dynamic>{'value': i * 10},
                  replaceKey: 'brightness')
              .then<Object>((r) => r)
              .catchError((Object e) => e),
      ]);

      // 第 1 条发出 (inflight)；2-4 被 5 替换；5 排队后发出
      final replaced = results.whereType<StateError>().toList();
      expect(replaced.length, 3, reason: '中间 3 条被替换');
      for (final error in replaced) {
        expect(error.message, contains('已被新命令替换'));
      }
      final responses = results.whereType<DeviceResponse>().toList();
      expect(responses.length, 2, reason: '首尾两条成功');

      // 设备实际只收到 2 条命令 (第一条 + 最后一条)
      expect(device.receivedCommands.length, 2);
      expect(device.receivedCommands.last.params['value'], 50);
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
