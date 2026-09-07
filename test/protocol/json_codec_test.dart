import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:myhome/protocol/ble_frame.dart';
import 'package:myhome/protocol/json_codec.dart';
import 'package:myhome/protocol/protocol_messages.dart';

void main() {
  const codec = JsonCodec();

  Map<String, dynamic> decodeJson(List<int> bytes) =>
      jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;

  group('Command (§10.2)', () {
    test('encode 与 doc 示例逐字对齐', () {
      final bytes = codec.encode(
        const DeviceCommand(
          requestId: 78231,
          cmd: 'light.set',
          params: <String, dynamic>{'brightness': 80},
        ),
      );

      expect(decodeJson(bytes), <String, dynamic>{
        'request_id': 78231,
        'cmd': 'light.set',
        'params': <String, dynamic>{'brightness': 80},
      });
    });

    test('round-trip: encode → decode 全字段一致', () {
      final command = DeviceCommand(
        requestId: 78231,
        cmd: 'scene.apply',
        params: <String, dynamic>{
          'name': '阅读模式',
          'levels': <int>[10, 20, 30],
        },
      );

      final decoded =
          codec.decode(FrameType.command, codec.encode(command)) as DeviceCommand;

      expect(decoded.requestId, command.requestId);
      expect(decoded.cmd, command.cmd);
      expect(decoded.params, command.params);
      expect(decoded.frameType, FrameType.command);
    });

    test('缺 cmd 字段 → ProtocolException', () {
      expect(
        () => codec.decode(
          FrameType.command,
          utf8.encode('{"request_id": 1}'),
        ),
        throwsA(isA<ProtocolException>()),
      );
    });

    test('request_id 非整数 → ProtocolException', () {
      expect(
        () => codec.decode(
          FrameType.command,
          utf8.encode('{"request_id": "abc", "cmd": "x"}'),
        ),
        throwsA(isA<ProtocolException>()),
      );
    });
  });

  group('Response (§10.3/§10.5)', () {
    test('成功响应与 doc 示例对齐', () {
      final bytes = codec.encode(
        const DeviceResponse(
          requestId: 78231,
          data: <String, dynamic>{'brightness': 80},
        ),
      );

      expect(decodeJson(bytes), <String, dynamic>{
        'request_id': 78231,
        'status': 'ok',
        'data': <String, dynamic>{'brightness': 80},
      });
    });

    test('错误响应与 doc 示例对齐 (code 3001)', () {
      final bytes = codec.encode(
        const DeviceResponse(
          requestId: 78231,
          status: 'error',
          error: DeviceError(code: 3001, message: 'Invalid parameter'),
        ),
      );

      expect(decodeJson(bytes), <String, dynamic>{
        'request_id': 78231,
        'status': 'error',
        'error': <String, dynamic>{'code': 3001, 'message': 'Invalid parameter'},
      });
    });

    test('round-trip: 错误响应', () {
      final decoded = codec.decode(
        FrameType.response,
        codec.encode(
          const DeviceResponse(
            requestId: 9,
            status: 'error',
            error: DeviceError(code: ProtocolErrorCodes.busy, message: 'busy'),
          ),
        ),
      ) as DeviceResponse;

      expect(decoded.isOk, isFalse);
      expect(decoded.error?.code, ProtocolErrorCodes.busy);
      expect(decoded.error?.message, 'busy');
    });

    test('round-trip: 成功响应 isOk', () {
      final decoded = codec.decode(
        FrameType.response,
        codec.encode(const DeviceResponse(requestId: 1)),
      ) as DeviceResponse;

      expect(decoded.isOk, isTrue);
      expect(decoded.data, const <String, dynamic>{});
    });
  });

  group('Event (§10.4)', () {
    test('encode 与 doc 示例对齐', () {
      final bytes = codec.encode(
        const DeviceEvent(
          event: 'temperature.changed',
          data: <String, dynamic>{'value': 25.5},
        ),
      );

      expect(decodeJson(bytes), <String, dynamic>{
        'event': 'temperature.changed',
        'data': <String, dynamic>{'value': 25.5},
      });
    });

    test('round-trip', () {
      final decoded = codec.decode(
        FrameType.event,
        codec.encode(
          const DeviceEvent(event: 'power.changed', data: <String, dynamic>{'on': true}),
        ),
      ) as DeviceEvent;

      expect(decoded.event, 'power.changed');
      expect(decoded.data, <String, dynamic>{'on': true});
    });
  });

  group('State / Patch (Phase 11 完善语义)', () {
    test('State round-trip', () {
      final decoded = codec.decode(
        FrameType.state,
        codec.encode(
          const DeviceState(
            version: 100,
            state: <String, dynamic>{'power': true, 'brightness': 80},
          ),
        ),
      ) as DeviceState;

      expect(decoded.version, 100);
      expect(decoded.state['power'], isTrue);
    });

    test('Patch encode 保留 "type":"patch" 字段 (§16.3 示例对齐)', () {
      final bytes = codec.encode(
        const DevicePatch(
          version: 103,
          ops: <Map<String, dynamic>>[
            <String, dynamic>{'op': 'replace', 'path': '/brightness', 'value': 60},
          ],
        ),
      );

      expect(decodeJson(bytes), <String, dynamic>{
        'type': 'patch',
        'version': 103,
        'ops': <Map<String, dynamic>>[
          <String, dynamic>{'op': 'replace', 'path': '/brightness', 'value': 60},
        ],
      });
    });
  });

  group('异常与边界', () {
    test('非业务帧类型 (ACK 0x10) → ProtocolException', () {
      expect(
        () => codec.decode(FrameType.ack, utf8.encode('{}')),
        throwsA(isA<ProtocolException>()),
      );
    });

    test('非法 JSON → ProtocolException', () {
      expect(
        () => codec.decode(FrameType.command, utf8.encode('not-json{{{')),
        throwsA(isA<ProtocolException>()),
      );
    });

    test('JSON 顶层非对象 → ProtocolException', () {
      expect(
        () => codec.decode(FrameType.command, utf8.encode('[1,2,3]')),
        throwsA(isA<ProtocolException>()),
      );
    });

    test('Unicode 参数 round-trip', () {
      final decoded = codec.decode(
        FrameType.command,
        codec.encode(
          DeviceCommand(
            requestId: 1,
            cmd: 'display.set',
            params: <String, dynamic>{'text': '你好，设备 👋'},
          ),
        ),
      ) as DeviceCommand;

      expect(decoded.params['text'], '你好，设备 👋');
    });
  });

  group('FrameType 注册表 (§10.1)', () {
    test('新增类型通过 BleFrame.validate', () {
      for (final type in <int>[
        FrameType.hello,
        FrameType.helloAck,
        FrameType.ping,
        FrameType.pong,
        FrameType.resourceRequest,
        FrameType.resourceResponse,
      ]) {
        final frame = BleFrame(
          version: BleFrame.currentVersion,
          type: type,
          flags: 0,
          sequence: 0,
          payload: const <int>[],
        );
        expect(frame.encode(), isNotNull, reason: 'type=0x${type.toRadixString(16)}');
      }
    });
  });
}
