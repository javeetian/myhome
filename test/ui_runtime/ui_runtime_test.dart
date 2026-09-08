import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:myhome/device/device_client.dart';
import 'package:myhome/device/device_manifest.dart';
import 'package:myhome/protocol/protocol_messages.dart';
import 'package:myhome/ui_runtime/ui_cache.dart';
import 'package:myhome/ui_runtime/ui_package.dart';
import 'package:myhome/ui_runtime/ui_runtime.dart';

import '../protocol/fake_ble_device.dart';

/// UiRuntime (WORK_V2 §15.3) 加载编排测试。
void main() {
  late FakeBleDevice device;
  late DeviceClient client;
  late Directory tempDir;
  late UiCache cache;
  late UiRuntime runtime;

  final pkg = UiPackage.pack(<String, Uint8List>{
    'index.html': Uint8List.fromList(utf8.encode('<html><body>v1</body></html>')),
    'style.css': Uint8List.fromList(utf8.encode('body{}')),
    'assets/icon.svg': Uint8List.fromList(utf8.encode('<svg/>')),
  });

  /// 脚本化设备：提供 manifest.json + ui.pkg。
  void serveUi({
    Map<String, dynamic>? manifestOverride,
    List<int>? pkgBytes,
  }) {
    final manifest = <String, dynamic>{
      'protocol': 1,
      'ui_version': '1.2.3',
      'device': <String, dynamic>{'type': 'light', 'model': 'fake-1'},
      'entry': 'index.html',
      'capabilities': <String>['power', 'brightness'],
      ...?manifestOverride,
    };
    device.onResource = (request) {
      switch (request.path) {
        case 'manifest.json':
          return DeviceResourceResponse(
            requestId: request.requestId,
            data: Uint8List.fromList(utf8.encode(jsonEncode(manifest))),
          );
        case 'ui.pkg':
          return DeviceResourceResponse(
            requestId: request.requestId,
            data: Uint8List.fromList(pkgBytes ?? pkg),
          );
        default:
          return DeviceResourceResponse(
            requestId: request.requestId,
            status: 'error',
            error: const DeviceError(code: 5001, message: 'not found'),
          );
      }
    };
  }

  setUp(() async {
    device = FakeBleDevice();
    client = DeviceClient(transport: device, deviceId: 'dev-1');
    await client.connect();
    tempDir = Directory.systemTemp.createTempSync('ui_runtime_test');
    cache = UiCache(tempDir.path);
    runtime = UiRuntime(client: client, cache: cache);
  });

  tearDown(() async {
    await client.dispose();
    await device.dispose();
    tempDir.deleteSync(recursive: true);
  });

  test('loadUi：manifest → 下载 ui.pkg → 解包缓存 (§15.3)', () async {
    serveUi();
    final result = await runtime.loadUi();

    expect(result.manifest.uiVersion, '1.2.3');
    expect(result.manifest.deviceType, 'light');
    expect(result.manifest.capabilities, <String>['power', 'brightness']);
    expect(result.rootDir, cache.versionDir('dev-1', '1.2.3'));
    expect(File(p.join(result.rootDir, 'index.html')).existsSync(), isTrue);
    expect(File(p.join(result.rootDir, 'assets/icon.svg')).existsSync(), isTrue);
  });

  test('缓存命中：第二次加载不重复下载 ui.pkg (§15.3)', () async {
    final downloads = <String>[];
    serveUi();
    device.onResource = (request) {
      downloads.add(request.path);
      switch (request.path) {
        case 'manifest.json':
          return DeviceResourceResponse(
            requestId: request.requestId,
            data: Uint8List.fromList(utf8.encode(jsonEncode(<String, dynamic>{
              'protocol': 1,
              'ui_version': '1.2.3',
            }))),
          );
        case 'ui.pkg':
          return DeviceResourceResponse(
            requestId: request.requestId,
            data: Uint8List.fromList(pkg),
          );
        default:
          return null;
      }
    };

    final first = await runtime.loadUi();
    final second = await runtime.loadUi();

    expect(first.rootDir, second.rootDir);
    expect(downloads, <String>['manifest.json', 'ui.pkg', 'manifest.json']);
  });

  test('SHA256 校验失败 → 抛异常 (§15.5)', () async {
    serveUi(manifestOverride: <String, dynamic>{
      'package': <String, dynamic>{
        'size': pkg.length,
        'sha256': 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef',
      },
    });
    await expectLater(runtime.loadUi(), throwsA(isA<StateError>()));
    expect(cache.lookup('dev-1', '1.2.3'), isNull);
  });

  test('SHA256 正确 → 通过', () async {
    serveUi(manifestOverride: <String, dynamic>{
      'package': <String, dynamic>{
        'size': pkg.length,
        'sha256': sha256.convert(pkg).toString(),
      },
    });
    final result = await runtime.loadUi();
    expect(result.rootDir, cache.versionDir('dev-1', '1.2.3'));
  });

  test('协议版本不支持 → UnsupportedProtocolError (§24)', () async {
    serveUi(manifestOverride: <String, dynamic>{'protocol': 99});
    await expectLater(runtime.loadUi(), throwsA(isA<UnsupportedProtocolError>()));
  });

  test('manifest.json 非法 JSON → StateError', () async {
    device.onResource = (request) => DeviceResourceResponse(
          requestId: request.requestId,
          data: Uint8List.fromList(utf8.encode('not json')),
        );
    await expectLater(runtime.loadUi(), throwsA(isA<StateError>()));
  });
}
