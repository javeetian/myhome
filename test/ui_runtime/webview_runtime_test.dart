import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:myhome/device/device_client.dart';
import 'package:myhome/ui_runtime/js_bridge.dart';
import 'package:myhome/ui_runtime/ui_server.dart';

import '../protocol/fake_ble_device.dart';

/// WebView Runtime (WORK_V2 §14, Phase 9) 测试：
/// Device API Runtime 注入 (纯 Dart) + 经 UiServer 的服务与注入。
void main() {
  group('injectDeviceApi (纯 Dart)', () {
    test('注入到 <head> 之后', () {
      const html = '<!DOCTYPE html><html><head><title>t</title></head><body>x</body></html>';
      final result = injectDeviceApi(html);
      expect(result, contains('<head><script src="__device_api.js"></script><title>t</title>'));
      expect(result, contains('<body>x</body>'));
    });

    test('无 <head> 时注入到 <html> 之后', () {
      const html = '<html lang="zh"><body>x</body></html>';
      final result = injectDeviceApi(html);
      expect(
        result,
        '<html lang="zh"><script src="__device_api.js"></script><body>x</body></html>',
      );
    });

    test('无 <html> 时前置', () {
      expect(injectDeviceApi('hello'), '<script src="__device_api.js"></script>hello');
    });
  });

  group('UiServer WebView Runtime', () {
    late FakeBleDevice device;
    late DeviceClient client;
    late UiServer server;
    late HttpClient http;
    late Directory staticRoot;
    late String token;

    Future<Map<String, dynamic>> get(String path) async {
      final request =
          await http.openUrl('GET', Uri.parse('http://127.0.0.1:${server.port}$path'));
      final response = await request.close();
      final text = await utf8.decoder.bind(response).join();
      return <String, dynamic>{
        'statusCode': response.statusCode,
        'contentType': response.headers.contentType?.mimeType,
        'body': text,
      };
    }

    setUp(() async {
      device = FakeBleDevice();
      client = DeviceClient(transport: device, deviceId: 'fake-1');
      await client.connect();
      staticRoot = Directory.systemTemp.createTempSync('webview_runtime_test');
      File('${staticRoot.path}/index.html').writeAsStringSync(
        '<!DOCTYPE html><html><head><meta charset="utf-8"></head>'
        '<body><h1>device ui</h1></body></html>',
      );
      File('${staticRoot.path}/style.css').writeAsStringSync('h1 { color: red; }');
      server = UiServer(client: client, staticRoot: staticRoot.path);
      await server.start();
      http = HttpClient();
      final entry = server.entryUrl!;
      token = entry.substring(entry.lastIndexOf('/s/') + 3, entry.length - 1);
    });

    tearDown(() async {
      http.close(force: true);
      await server.stop();
      await client.dispose();
      await device.dispose();
      staticRoot.deleteSync(recursive: true);
    });

    test('HTML 页面自动注入 Device API Runtime (§14.3/§14.5)', () async {
      final result = await get('/s/$token/');
      expect(result['statusCode'], 200);
      expect(result['contentType'], 'text/html');
      expect(
        result['body'],
        contains('<head><script src="__device_api.js"></script><meta charset="utf-8">'),
      );
      expect(result['body'], contains('<h1>device ui</h1>'));
    });

    test('非 HTML 资源不注入', () async {
      final result = await get('/s/$token/style.css');
      expect(result['statusCode'], 200);
      expect(result['body'], 'h1 { color: red; }');
      expect(result['body'], isNot(contains('__device_api.js')));
    });

    test('__device_api.js 由服务器提供，含 deviceApi / deviceState', () async {
      final result = await get('/s/$token/__device_api.js');
      expect(result['statusCode'], 200);
      expect(result['contentType'], 'application/javascript');
      expect(result['body'], contains('window.deviceApi'));
      expect(result['body'], contains('window.deviceState'));
      expect(result['body'], contains('deviceStateVersion'));
      expect(result['body'], contains('onState'));
      expect(result['body'], contains('onEvent'));
    });
  });
}
