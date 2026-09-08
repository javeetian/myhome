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
