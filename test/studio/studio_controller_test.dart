import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:myhome/device/demo_device.dart';
import 'package:myhome/device/virtual_light.dart';
import 'package:myhome/studio/studio_controller.dart';
import 'package:myhome/ui_runtime/ui_cache.dart';

/// Device Studio 控制器 (WORK_V3 §28/§29) 测试：
/// 模拟设备会话全流程，脱离真实 BLE。
void main() {
  late Directory tempDir;
  late ProviderContainer container;

  ProviderContainer createContainer() {
    return ProviderContainer(
      overrides: [
        studioControllerProvider
            .overrideWith(() => StudioController(cache: UiCache(tempDir.path))),
      ],
    );
  }

  Future<void> waitFor(
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('等待条件超时');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('studio_test');
    container = createContainer();
  });

  tearDown(() async {
    await container.read(studioControllerProvider.notifier).stop();
    container.dispose();
    tempDir.deleteSync(recursive: true);
  });

  test('初始 idle：无设备无 UI', () {
    final state = container.read(studioControllerProvider);
    expect(state.isRunning, isFalse);
    expect(state.entryUrl, isNull);
  });

  test('启动 VirtualLight：握手 → 状态 → UI 服务 (§29)', () async {
    final ok = await container
        .read(studioControllerProvider.notifier)
        .start(VirtualLight());

    expect(ok, isTrue);
    final state = container.read(studioControllerProvider);
    expect(state.isRunning, isTrue);
    expect(state.helloAck?.deviceModel, 'L100');
    expect(state.currentState?.state['power'], isFalse);
    expect(state.entryUrl, startsWith('http://127.0.0.1:'));
  });

  test('启动 DemoDevice：UI 包解压 → 静态服务 + 协议日志', () async {
    final ok = await container
        .read(studioControllerProvider.notifier)
        .start(DemoDevice());

    expect(ok, isTrue);
    final state = container.read(studioControllerProvider);
    expect(state.entryUrl, isNotNull);
    // UI 包已解压缓存 (index.html 存在)
    expect(
      Directory('${tempDir.path}/${DemoDevice().deviceId}/${DemoDevice().uiVersion}')
          .existsSync(),
      isTrue,
    );
    // 协议日志有 TX/RX 帧
    expect(state.protocolLog.any((l) => l.contains('TX') || l.contains('发送')), isTrue);
    expect(state.protocolLog.any((l) => l.contains('RX')), isTrue);
  });

  test('Inspector 命令：set_power → 状态更新', () async {
    final notifier = container.read(studioControllerProvider.notifier);
    await notifier.start(VirtualLight());

    final response = await notifier
        .sendCommand('light.set_power', <String, dynamic>{'power': true});
    expect(response?.isOk, isTrue);

    await waitFor(
        () => container.read(studioControllerProvider).currentState?.state['power'] == true);
  });

  test('重置设备：状态复位 (§29 Reset Device)', () async {
    final notifier = container.read(studioControllerProvider.notifier);
    await notifier.start(VirtualLight());
    await notifier.sendCommand('light.set_brightness', <String, dynamic>{'value': 10});
    await waitFor(() =>
        container.read(studioControllerProvider).currentState?.state['brightness'] == 10);

    final ok = await notifier.reset();
    expect(ok, isTrue);
    await waitFor(() =>
        container.read(studioControllerProvider).currentState?.state['brightness'] == 80);
  });

  test('断开：回 idle', () async {
    final notifier = container.read(studioControllerProvider.notifier);
    await notifier.start(VirtualLight());
    expect(container.read(studioControllerProvider).isRunning, isTrue);

    await notifier.stop();
    expect(container.read(studioControllerProvider).isRunning, isFalse);
  });
}
