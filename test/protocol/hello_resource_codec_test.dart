import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:myhome/protocol/ble_frame.dart';
import 'package:myhome/protocol/json_codec.dart';
import 'package:myhome/protocol/protocol_messages.dart';

/// Phase 10 新增协议消息 (WORK_V2 §39/§27) 的编解码测试。
void main() {
  const codec = JsonCodec();

  group('HELLO / HELLO_ACK (§39)', () {
    test('DeviceHello round-trip', () {
      final encoded = codec.encode(const DeviceHello(requestId: 7));
      final decoded =
          codec.decode(FrameType.hello, encoded) as DeviceHello;
      expect(decoded.requestId, 7);
      expect(decoded.protocolVersion, 1);
    });

    test('DeviceHelloAck 全字段 round-trip', () {
      const ack = DeviceHelloAck(
        requestId: 7,
        protocolVersion: 1,
        deviceType: 'light',
        deviceModel: 'AC7014',
        firmwareVersion: '1.2.0',
        uiVersion: '1.2.3',
        capabilities: <String>['power', 'brightness', 'rgb'],
      );
      final decoded =
          codec.decode(FrameType.helloAck, codec.encode(ack)) as DeviceHelloAck;
      expect(decoded.requestId, 7);
      expect(decoded.deviceType, 'light');
      expect(decoded.deviceModel, 'AC7014');
      expect(decoded.firmwareVersion, '1.2.0');
      expect(decoded.uiVersion, '1.2.3');
      expect(decoded.capabilities, <String>['power', 'brightness', 'rgb']);
    });

    test('DeviceHelloAck 可选字段缺省值', () {
      final decoded = codec.decode(
        FrameType.helloAck,
        codec.encode(const DeviceHelloAck(requestId: 1)),
      ) as DeviceHelloAck;
      expect(decoded.deviceType, '');
      expect(decoded.capabilities, isEmpty);
    });

    test('HELLO 缺 request_id → ProtocolException', () {
      expect(
        () => codec.decode(
          FrameType.hello,
          utf8.encode('{"protocol_version":1}'),
        ),
        throwsA(isA<ProtocolException>()),
      );
    });
  });

  group('RESOURCE_REQUEST / RESPONSE (§27)', () {
    test('DeviceResourceRequest round-trip', () {
      final decoded = codec.decode(
        FrameType.resourceRequest,
        codec.encode(const DeviceResourceRequest(requestId: 3, path: 'ui.pkg')),
      ) as DeviceResourceRequest;
      expect(decoded.requestId, 3);
      expect(decoded.path, 'ui.pkg');
    });

    test('DeviceResourceResponse 二进制数据 round-trip (base64)', () {
      final binary = Uint8List.fromList(<int>[0, 1, 2, 255, 254, 128]);
      final response = DeviceResourceResponse(
        requestId: 3,
        data: binary,
      );
      final decoded = codec.decode(
        FrameType.resourceResponse,
        codec.encode(response),
      ) as DeviceResourceResponse;
      expect(decoded.isOk, isTrue);
      expect(decoded.data, binary);
    });

    test('DeviceResourceResponse 错误响应 round-trip', () {
      final response = DeviceResourceResponse(
        requestId: 3,
        status: 'error',
        error: const DeviceError(code: 5001, message: 'not found'),
      );
      final decoded = codec.decode(
        FrameType.resourceResponse,
        codec.encode(response),
      ) as DeviceResourceResponse;
      expect(decoded.isOk, isFalse);
      expect(decoded.error?.code, 5001);
      expect(decoded.error?.message, 'not found');
    });

    test('RESOURCE_REQUEST 缺 path → ProtocolException', () {
      expect(
        () => codec.decode(
          FrameType.resourceRequest,
          utf8.encode('{"request_id":3}'),
        ),
        throwsA(isA<ProtocolException>()),
      );
    });
  });

  group('STATE_REQUEST (§16.5/§16.6)', () {
    test('DeviceStateRequest round-trip', () {
      final decoded = codec.decode(
        FrameType.stateRequest,
        codec.encode(const DeviceStateRequest(requestId: 42)),
      ) as DeviceStateRequest;
      expect(decoded.requestId, 42);
    });

    test('缺 request_id → ProtocolException', () {
      expect(
        () => codec.decode(FrameType.stateRequest, utf8.encode('{}')),
        throwsA(isA<ProtocolException>()),
      );
    });
  });
}
