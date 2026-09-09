import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

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

  test('Smart Light：构建产物缺失时现场打包 (QUICKSTART §2)', () async {
    // 注入临时路径配置
    final uiDir = Directory('${tempDir.path}/smart_light_ui');
    uiDir.createSync();
    File('${uiDir.path}/manifest.json').writeAsStringSync(jsonEncode(<String, dynamic>{
      'package': 'light_ui',
      'version': '1.0.0',
      'device': <String, dynamic>{'type': 'light', 'model': 'L100'},
      'protocol': <String, dynamic>{'version': 1},
      'entry': 'index.html',
    }));
    File('${uiDir.path}/index.html').writeAsStringSync('<html>fresh</html>');
    final pkgPath = '${tempDir.path}/out/ui.pkg';

    StudioController.smartLightUiDir = uiDir.path;
    StudioController.smartLightPkgPath = pkgPath;
    addTearDown(() {
      StudioController.smartLightUiDir = 'devices/smart_light/ui';
      StudioController.smartLightPkgPath = 'devices/smart_light/build/ui.pkg';
    });

    final notifier = container.read(studioControllerProvider.notifier);
    expect(File(pkgPath).existsSync(), isFalse);
    final pkg = await notifier.loadSmartLightPkg();
    expect(pkg, isNotNull);
    expect(File(pkgPath).existsSync(), isTrue, reason: '现场打包产物落盘');

    // 产物就绪后启动 → UI 正常 (staticRoot 非空)
    final ok = await notifier.start(VirtualLight(uiPkgBytes: pkg));
    expect(ok, isTrue);
    expect(
      File('${tempDir.path}/light/L100/1.0.0/index.html').existsSync(),
      isTrue,
    );
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
  group('resolvePath (macOS 沙箱 CWD 场景)', () {
    late Directory project; // 模拟项目根
    late Directory sandbox; // 模拟 macOS 沙箱容器 CWD
    late Directory appBundle; // 模拟 .app 内可执行文件目录

    setUp(() {
      project = Directory.systemTemp.createTempSync('myhome_project_');
      sandbox = Directory.systemTemp.createTempSync('myhome_sandbox_');
      appBundle = Directory(
          '${project.path}/build/macos/Build/Products/Debug/myhome.app/Contents/MacOS')
        ..createSync(recursive: true);
      File('${project.path}/pubspec.yaml').writeAsStringSync('name: myhome');
      Directory('${project.path}/devices/smart_light/ui')
          .createSync(recursive: true);
      File('${project.path}/devices/smart_light/ui/manifest.json')
          .writeAsStringSync('{}');
    });

    tearDown(() {
      project.deleteSync(recursive: true);
      sandbox.deleteSync(recursive: true);
    });

    test('相对路径：CWD 命中时直接用 (Windows 场景)', () {
      final resolved = StudioController.resolvePath(
        'devices/smart_light/ui',
        exeDir: appBundle,
        cwd: project, // CWD 即项目根
      );
      expect(resolved, p.join(project.path, 'devices/smart_light/ui'));
    });

    test('相对路径：CWD 是沙箱容器 → 从可执行文件向上找到项目根 (macOS)', () {
      final resolved = StudioController.resolvePath(
        'devices/smart_light/ui',
        exeDir: appBundle,
        cwd: sandbox, // macOS 沙箱 CWD ≠ 项目根
      );
      expect(resolved, p.join(project.path, 'devices/smart_light/ui'));
    });

    test('绝对路径直接返回 (测试注入场景)', () {
      final resolved = StudioController.resolvePath(
        '${sandbox.path}/ui',
        exeDir: appBundle,
        cwd: sandbox,
      );
      expect(resolved, '${sandbox.path}/ui');
    });
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
