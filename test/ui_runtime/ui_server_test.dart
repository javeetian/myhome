import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:myhome/device/device_client.dart';
import 'package:myhome/protocol/protocol_messages.dart';
import 'package:myhome/ui_runtime/ui_server.dart';

import '../protocol/fake_ble_device.dart';

/// UiServer / UiAdapter 集成测试 (WORK_V2 §13)。
/// 走真实 TCP 回环 (127.0.0.1 随机端口)，设备侧为脚本化 FakeBleDevice。
void main() {
  group('UiServer (WORK_V2 §13)', () {
    late FakeBleDevice device;
    late DeviceClient client;
    late UiServer server;
    late HttpClient http;
    late Directory staticRoot;

    String token = '';

    Future<Map<String, dynamic>> request(
      String path, {
      String method = 'GET',
      String? origin,
      String? body,
      bool raw = false,
    }) async {
      final url = Uri.parse('http://127.0.0.1:${server.port}$path');
      final request = await http.openUrl(method, url);
      if (origin != null) {
        request.headers.set('origin', origin);
      }
      if (body != null) {
        request.headers.set('content-type', 'application/json');
        request.write(body);
      }
      final response = await request.close();
      final text = await utf8.decoder.bind(response).join();
      final isJson =
          response.headers.contentType?.mimeType == 'application/json';
      return <String, dynamic>{
        'statusCode': response.statusCode,
        'contentType': response.headers.contentType?.mimeType,
        'body': raw
            ? text
            : (isJson && text.isNotEmpty ? jsonDecode(text) : text),
      };
    }

    setUp(() async {
      device = FakeBleDevice();
      client = DeviceClient(transport: device, deviceId: 'fake-1');
      await client.connect();
      staticRoot = Directory.systemTemp.createTempSync('ui_server_test');
      File('${staticRoot.path}/index.html')
          .writeAsStringSync('<html><body>hello</body></html>');
      File('${staticRoot.path}/style.css').writeAsStringSync('body{}');
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

    test('§13.5 随机端口 + 随机 token + entryUrl 格式', () async {
      expect(server.port, isNotNull);
      expect(server.port, greaterThan(0));
      expect(token.length, 32);
      expect(
        server.entryUrl,
        'http://127.0.0.1:${server.port}/s/$token/',
      );
    });

    test('§13.2 GET /api/device 返回设备信息', () async {
      final result = await request('/s/$token/api/device');
      expect(result['statusCode'], 200);
      expect(result['body'], <String, dynamic>{
        'device_id': 'fake-1',
        'protocol': 1,
        'connected': true,
      });
    });

    test('§13.3 POST /api/command → DeviceClient 往返', () async {
      final result = await request(
        '/s/$token/api/command',
        method: 'POST',
        body: '{"cmd":"led_on","params":{"brightness":80}}',
      );
      expect(result['statusCode'], 200);
      expect(result['body']['status'], 'ok');
      expect(result['body']['request_id'], 1);
      expect(result['body']['data'], <String, dynamic>{
        'echo': <String, dynamic>{'brightness': 80},
      });
      // 设备侧确实收到解析后的命令
      expect(device.receivedCommands.last.cmd, 'led_on');
      expect(device.receivedCommands.last.params, <String, dynamic>{'brightness': 80});
    });

    test('设备业务错误 (status=error) 正常返回 200', () async {
      device.onCommand = (command) => DeviceResponse(
            requestId: command.requestId,
            status: 'error',
            error: const DeviceError(code: 3002, message: 'unknown cmd'),
          );
      final result = await request(
        '/s/$token/api/command',
        method: 'POST',
        body: '{"cmd":"nope","params":{}}',
      );
      expect(result['statusCode'], 200);
      expect(result['body']['status'], 'error');
      expect(result['body']['error'], <String, dynamic>{
        'code': 3002,
        'message': 'unknown cmd',
      });
    });

    test('适配层坏请求 → 400 + 3001', () async {
      final cases = <(String, int)>[
        ('not json', 400),
        ('{"cmd":""}', 400),
        ('{"cmd":"x","params":[]}', 400),
      ];
      for (final (body, expected) in cases) {
        final result = await request(
          '/s/$token/api/command',
          method: 'POST',
          body: body,
        );
        expect(result['statusCode'], expected, reason: 'body=$body');
        expect(result['body']['error']['code'], 3001, reason: 'body=$body');
      }
    });

    test('§13.2 GET /api/state：有状态返回 / 无状态 404', () async {
      final before = await request('/s/$token/api/state');
      expect(before['statusCode'], 404);
      expect(before['body']['error']['code'], 2002);

      device.sendState(7, <String, dynamic>{'power': true, 'brightness': 80});
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final after = await request('/s/$token/api/state');
      expect(after['statusCode'], 200);
      expect(after['body'], <String, dynamic>{
        'version': 7,
        'state': <String, dynamic>{'power': true, 'brightness': 80},
      });
    });

    test('§13.2 GET /api/resource → 501 (Phase 10)', () async {
      final result = await request('/s/$token/api/resource/icon.png');
      expect(result['statusCode'], 501);
      expect(result['body']['error']['code'], 5001);
    });

    test('§13.5 无 token / 错误 token → 404', () async {
      final noToken = await request('/api/device');
      expect(noToken['statusCode'], 404);
      final wrongToken = await request('/s/00000000000000000000000000000000/api/device');
      expect(wrongToken['statusCode'], 404);
    });

    test('§13.5 非本机 Origin → 403', () async {
      final result = await request(
        '/s/$token/api/device',
        origin: 'https://evil.example.com',
      );
      expect(result['statusCode'], 403);
      // 本机 Origin 放行
      final local = await request(
        '/s/$token/api/device',
        origin: 'http://127.0.0.1:${server.port}',
      );
      expect(local['statusCode'], 200);
    });

    test('§14.4 WS 推送 state / event / patch → WebView', () async {
      final channel = WebSocketChannel.connect(
        Uri.parse('ws://127.0.0.1:${server.port}/s/$token/ws'),
      );
      await channel.ready;

      final messages = <Map<String, dynamic>>[];
      final gotThree = Completer<void>();
      final sub = channel.stream.listen((data) {
        messages.add(jsonDecode(data as String) as Map<String, dynamic>);
        if (messages.length == 3 && !gotThree.isCompleted) {
          gotThree.complete();
        }
      });

      device.sendState(1, <String, dynamic>{'power': true});
      device.sendEvent('temperature.changed', <String, dynamic>{'value': 25.5});
      device.sendPatch(2, <Map<String, dynamic>>[
        <String, dynamic>{'op': 'replace', 'path': '/brightness', 'value': 60},
      ]);
      await gotThree.future.timeout(const Duration(seconds: 3));

      expect(messages[0], <String, dynamic>{
        'type': 'state',
        'version': 1,
        'state': <String, dynamic>{'power': true},
      });
      expect(messages[1], <String, dynamic>{
        'type': 'event',
        'event': 'temperature.changed',
        'data': <String, dynamic>{'value': 25.5},
      });
      expect(messages[2]['type'], 'patch');
      expect(messages[2]['version'], 2);

      await sub.cancel();
      await channel.sink.close();
    });

    test('静态服务：index.html / css / 目录穿越防护', () async {
      final index = await request('/s/$token/', raw: true);
      expect(index['statusCode'], 200);
      expect(index['contentType'], 'text/html');
      expect(index['body'], contains('hello'));

      final css = await request('/s/$token/style.css', raw: true);
      expect(css['statusCode'], 200);
      expect(css['contentType'], 'text/css');

      final traversal = await request('/s/$token/%2e%2e/secret.txt', raw: true);
      expect(traversal['statusCode'], anyOf(403, 404));
    });
  });
}
