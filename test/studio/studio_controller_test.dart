import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:myhome/device/demo_device.dart';
import 'package:myhome/device/virtual_light.dart';
import 'package:myhome/studio/studio_controller.dart';
import 'package:myhome/ui_runtime/ui_cache.dart';
import 'package:myhome/ui_runtime/ui_package.dart';

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
      Directory('${tempDir.path}/light/demo-1/${DemoDevice().uiVersion}')
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

  test('HTTP Server 重启恢复 (Phase 35 Crash Recovery)', () async {
    final notifier = container.read(studioControllerProvider.notifier);
    await notifier.start(VirtualLight());
    final firstUrl = container.read(studioControllerProvider).entryUrl;
    expect(firstUrl, isNotNull);

    await notifier.stop();
    expect(container.read(studioControllerProvider).entryUrl, isNull);

    // 重启：新会话重新握手/同步/UI 服务 (缓存命中)
    final ok = await notifier.start(VirtualLight());
    expect(ok, isTrue);
    final secondUrl = container.read(studioControllerProvider).entryUrl;
    expect(secondUrl, isNotNull);
    expect(container.read(studioControllerProvider).currentState, isNotNull);
  });

  test('UI Hot Reload：源文件变化 → 重打包 → reloadCount++ (Phase 37)', () async {
    // 建 UI 源目录
    final uiDir = Directory('${tempDir.path}/ui_src');
    uiDir.createSync();
    File('${uiDir.path}/manifest.json').writeAsStringSync(jsonEncode(<String, dynamic>{
      'package': 'light_ui',
      'version': '1.0.0',
      'device': <String, dynamic>{'type': 'light', 'model': 'L100'},
      'protocol': <String, dynamic>{'version': 1},
      'entry': 'index.html',
    }));
    final indexFile = File('${uiDir.path}/index.html')
      ..writeAsStringSync('<html>v1</html>');
    final outPkg = '${tempDir.path}/build/ui.pkg';
    File(outPkg)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(uiPkgFrom(uiDir));

    final notifier = container.read(studioControllerProvider.notifier);
    final ok = await notifier.start(VirtualLight(uiPkgBytes: File(outPkg).readAsBytesSync()));
    expect(ok, isTrue);
    expect(container.read(studioControllerProvider).reloadCount, 0);

    notifier.startUiWatch(uiDir.path, outPkg);
    // 修改源文件 → 触发重打包重载
    indexFile.writeAsStringSync('<html>v2</html>');
    await waitFor(() =>
        container.read(studioControllerProvider).reloadCount >= 1,
        timeout: const Duration(seconds: 5));

    // 缓存目录内容已更新
    final cacheDir = Directory('${tempDir.path}/light/L100/1.0.0');
    expect(
      File('${cacheDir.path}/index.html').readAsStringSync(),
      '<html>v2</html>',
    );
  });
}

Uint8List uiPkgFrom(Directory dir) {
  final files = <String, Uint8List>{};
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is File) {
      final rel =
          entity.path.substring(dir.path.length + 1).replaceAll('\\', '/');
      files[rel] = Uint8List.fromList(entity.readAsBytesSync());
    }
  }
  return UiPackage.pack(files);
}
