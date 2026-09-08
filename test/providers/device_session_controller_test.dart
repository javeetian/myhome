import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:myhome/device/connection_phase.dart';
import 'package:myhome/providers/ble_provider.dart';
import 'package:myhome/providers/device_session_provider.dart';

import '../protocol/fake_ble_device.dart';

void main() {
  late FakeBleDevice device;
  late ProviderContainer container;

  ProviderContainer createContainer() {
    return ProviderContainer(
      overrides: [bleTransportProvider.overrideWithValue(device)],
    );
  }

  setUp(() {
    device = FakeBleDevice();
    container = createContainer();
  });

  tearDown(() {
    container.dispose();
    return device.dispose();
  });

  /// 轮询等待条件成立 (Riverpod 3 微任务批处理下观察中间态)。
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

  test('初始状态 disconnected，无 client (§12.6)', () {
    final session = container.read(deviceSessionProvider);

    expect(session.phase, ConnectionPhase.disconnected);
    expect(session.client, isNull);
    expect(container.read(connectionPhaseProvider), ConnectionPhase.disconnected);
    expect(container.read(deviceClientProvider), isNull);
    expect(container.read(deviceStateProvider), isNull);
  });

  test('connect 成功: connecting → connected', () async {
    // Riverpod 3 微任务批处理会合并瞬间状态，用门控观察中间态
    device.connectGate = Completer<void>();
    final notifier = container.read(deviceSessionProvider.notifier);

    final connectFuture = notifier.connect('dev-1');
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(connectionPhaseProvider),
      ConnectionPhase.connecting,
      reason: '连接未完成时应处于 connecting',
    );

    device.connectGate!.complete();
    await connectFuture;

    expect(container.read(connectionPhaseProvider), ConnectionPhase.connected);
    expect(container.read(deviceClientProvider), isNotNull);
  });

  test('connect 失败 → error 且记录错误信息', () async {
    device.rejectConnect = true;
    final notifier = container.read(deviceSessionProvider.notifier);

    await notifier.connect('dev-1');

    final session = container.read(deviceSessionProvider);
    expect(session.phase, ConnectionPhase.error);
    expect(session.error, contains('连接被拒绝'));
  });

  test('设备状态推送到 deviceStateProvider', () async {
    final notifier = container.read(deviceSessionProvider.notifier);
    await notifier.connect('dev-1');

    device.sendState(100, <String, dynamic>{'power': true});
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final state = container.read(deviceStateProvider);
    expect(state?.version, 100);
    expect(state?.state['power'], isTrue);
  });

  test('disconnect: connected → disconnecting → disconnected (§12.6 断线)', () async {
    final notifier = container.read(deviceSessionProvider.notifier);
    await notifier.connect('dev-1');

    await notifier.disconnect();

    final session = container.read(deviceSessionProvider);
    expect(session.phase, ConnectionPhase.disconnected);
    expect(session.client, isNull);
  });

  test('设备侧主动断开 → 会话回到 disconnected (§20)', () async {
    final notifier = container.read(deviceSessionProvider.notifier);
    await notifier.connect('dev-1');
    expect(container.read(connectionPhaseProvider), ConnectionPhase.connected);

    device.emitDisconnected();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(container.read(connectionPhaseProvider), ConnectionPhase.disconnected);
  });

  test('重复 connect 先释放旧会话', () async {
    final notifier = container.read(deviceSessionProvider.notifier);
    await notifier.connect('dev-1');
    final firstClient = container.read(deviceClientProvider);

    await notifier.connect('dev-2');
    final secondClient = container.read(deviceClientProvider);

    expect(container.read(connectionPhaseProvider), ConnectionPhase.connected);
    expect(identical(firstClient, secondClient), isFalse);
  });

  test('命令经会话 client 收发 (全链路)', () async {
    final notifier = container.read(deviceSessionProvider.notifier);
    await notifier.connect('dev-1');

    final response = await container
        .read(deviceClientProvider)!
        .command('ping', const <String, dynamic>{});

    expect(response.isOk, isTrue);
    expect(device.receivedCommands.single.cmd, 'ping');
  });

  test('connect 完成 HELLO 握手 (Phase 10 §39)', () async {
    final notifier = container.read(deviceSessionProvider.notifier);
    await notifier.connect('dev-1');

    final helloAck = container.read(deviceClientProvider)!.helloAck;
    expect(helloAck, isNotNull);
    expect(helloAck!.deviceType, 'fake');
    expect(helloAck.uiVersion, '0.0.0');
  });

  test('HELLO 无响应 → connect 失败进入 error', () async {
    device.onHello = (_) => null; // 设备不回 HELLO_ACK
    final notifier = container.read(deviceSessionProvider.notifier);
    await notifier.connect('dev-1'); // 内部 hello 超时由 commandTimeout 控制

    expect(container.read(connectionPhaseProvider), ConnectionPhase.error);
  }, timeout: const Timeout(Duration(seconds: 15)));

  test('connect 中间态: handshaking → syncingState (§12.6, Phase 11)', () async {
    device.helloDelay = const Duration(milliseconds: 100);
    device.pushInitialStateOnConnect = false;
    device.stateRequestDelay = const Duration(milliseconds: 100);
    final notifier = container.read(deviceSessionProvider.notifier);

    final connectFuture = notifier.connect('dev-1');
    await waitFor(() =>
        container.read(connectionPhaseProvider) == ConnectionPhase.handshaking);
    await waitFor(() =>
        container.read(connectionPhaseProvider) == ConnectionPhase.syncingState);
    await connectFuture;

    expect(container.read(connectionPhaseProvider), ConnectionPhase.connected);
    expect(container.read(deviceStateProvider), isNotNull);
  });

  test('connect 完成状态同步 (§16.6)', () async {
    final notifier = container.read(deviceSessionProvider.notifier);
    await notifier.connect('dev-1');

    expect(container.read(deviceStateProvider)?.version, 1);
    expect(container.read(deviceClientProvider)!.hasState, isTrue);
  });

  test('setPhase: loadingUi → connected (Phase 9 UI 加载)', () async {
    final notifier = container.read(deviceSessionProvider.notifier);
    await notifier.connect('dev-1');
    expect(container.read(connectionPhaseProvider), ConnectionPhase.connected);

    // UI Server 启动完成 → 加载 UI
    notifier.setPhase(ConnectionPhase.loadingUi);
    expect(container.read(connectionPhaseProvider), ConnectionPhase.loadingUi);

    // WebView 页面加载完成 → UI Ready
    notifier.setPhase(ConnectionPhase.connected);
    expect(container.read(connectionPhaseProvider), ConnectionPhase.connected);
  });

  test('setPhase: error 终态不可覆盖', () async {
    final notifier = container.read(deviceSessionProvider.notifier);
    device.rejectConnect = true;
    await notifier.connect('dev-1');
    expect(container.read(connectionPhaseProvider), ConnectionPhase.error);

    notifier.setPhase(ConnectionPhase.connected);
    expect(container.read(connectionPhaseProvider), ConnectionPhase.error);
  });

  test('setPhase: disconnected 离线态不可覆盖', () async {
    final notifier = container.read(deviceSessionProvider.notifier);
    await notifier.connect('dev-1');
    device.emitDisconnected();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(container.read(connectionPhaseProvider), ConnectionPhase.disconnected);

    notifier.setPhase(ConnectionPhase.loadingUi);
    expect(container.read(connectionPhaseProvider), ConnectionPhase.disconnected);
  });
}
