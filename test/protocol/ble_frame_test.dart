import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:myhome/protocol/ble_frame.dart';
import 'package:myhome/protocol/crc16.dart';
import 'package:myhome/protocol/frame_sequencer.dart';

void main() {
  BleFrame buildFrame({
    int version = BleFrame.currentVersion,
    int type = FrameType.command,
    int flags = 0,
    int sequence = 1,
    List<int> payload = const <int>[0xde, 0xad, 0xbe, 0xef],
  }) =>
      BleFrame(
        version: version,
        type: type,
        flags: flags,
        sequence: sequence,
        payload: payload,
      );

  /// 构造带合法 CRC 的原始帧字节 (模拟真实固件编码行为)。
  /// 用于测试 decode 侧的字段校验 —— encode() 自带 validate，
  /// 无法产生坏 Version / 坏 Type 的帧。
  List<int> rawFrame({
    int version = BleFrame.currentVersion,
    int type = FrameType.command,
    int flags = 0,
    int sequence = 1,
    List<int> payload = const <int>[0xde, 0xad, 0xbe, 0xef],
  }) {
    final body = <int>[
      version & 0xFF,
      type & 0xFF,
      flags & 0xFF,
      (sequence >> 8) & 0xFF,
      sequence & 0xFF,
      (payload.length >> 8) & 0xFF,
      payload.length & 0xFF,
      ...payload,
    ];
    final crc = crc16Ccitt(body);
    return <int>[...body, (crc >> 8) & 0xFF, crc & 0xFF];
  }

  group('encode / decode', () {
    test('正常 Frame：全字段往返一致', () {
      final frame = buildFrame(
        type: FrameType.command,
        flags: 0xA5,
        sequence: 0x1234,
        payload: <int>[1, 2, 3, 4, 5],
      );
      final bytes = frame.encode();

      // 头部布局：VER TYPE FLAGS SEQ(2B BE) LENGTH(2B BE)
      expect(bytes[0], BleFrame.currentVersion);
      expect(bytes[1], FrameType.command);
      expect(bytes[2], 0xA5);
      expect(bytes[3], 0x12, reason: 'SEQ 大端高字节');
      expect(bytes[4], 0x34, reason: 'SEQ 大端低字节');
      expect(bytes[5], 0x00);
      expect(bytes[6], 0x05);
      expect(bytes.length, BleFrame.headerSize + 5 + BleFrame.crcSize);

      final decoded = BleFrame.decode(bytes);
      expect(decoded.version, frame.version);
      expect(decoded.type, frame.type);
      expect(decoded.flags, frame.flags);
      expect(decoded.sequence, frame.sequence);
      expect(decoded.payload, frame.payload);
    });

    test('空 Payload：LENGTH=0 正常往返', () {
      final bytes = buildFrame(payload: const <int>[]).encode();
      expect(bytes.length, BleFrame.headerSize + BleFrame.crcSize);

      final decoded = BleFrame.decode(bytes);
      expect(decoded.payload, isEmpty);
    });

    test('最大 Payload (65535 字节) 正常往返', () {
      final payload = Uint8List.fromList(
        List<int>.generate(BleFrame.maxPayloadSize, (i) => i & 0xFF),
      );
      final bytes = buildFrame(payload: payload).encode();
      expect(bytes.length, BleFrame.headerSize + BleFrame.maxPayloadSize + BleFrame.crcSize);

      final decoded = BleFrame.decode(bytes);
      expect(decoded.payload.length, BleFrame.maxPayloadSize);
      expect(decoded.payload.first, 0);
      expect(decoded.payload.last, 0xFE);
    });

    test('SEQ 边界值 0 / 0xFFFF 往返一致', () {
      for (final seq in <int>[0, 0xFFFF]) {
        final decoded = BleFrame.decode(buildFrame(sequence: seq).encode());
        expect(decoded.sequence, seq);
      }
    });
  });

  group('异常路径 (§7.3 丢弃语义)', () {
    test('CRC 错误：翻转 Payload 一个字节', () {
      final bytes = buildFrame().encode();
      bytes[bytes.length - BleFrame.crcSize - 1] ^= 0xFF; // 破坏 Payload 尾字节

      expect(
        () => BleFrame.decode(bytes),
        throwsA(isA<FrameException>().having((e) => e.message, 'message', contains('CRC'))),
      );
    });

    test('CRC 错误：翻转头部一个字节', () {
      final bytes = buildFrame().encode();
      bytes[1] ^= 0xFF; // 破坏 TYPE 字节 (CRC 覆盖范围含 Header)

      expect(
        () => BleFrame.decode(bytes),
        throwsA(isA<FrameException>().having((e) => e.message, 'message', contains('CRC'))),
      );
    });

    test('Length 错误：声明长度与实际不符', () {
      final bytes = buildFrame(payload: <int>[1, 2, 3]).encode();
      bytes[6] = 9; // LENGTH 低字节 3 → 9，总长不再匹配

      expect(
        () => BleFrame.decode(bytes),
        throwsA(isA<FrameException>().having((e) => e.message, 'message', contains('Length'))),
      );
    });

    test('Length 错误：缓冲区被截断', () {
      final bytes = buildFrame(payload: <int>[1, 2, 3]).encode();

      expect(
        () => BleFrame.decode(bytes.sublist(0, bytes.length - 1)),
        throwsA(isA<FrameException>().having((e) => e.message, 'message', contains('Length'))),
      );
    });

    test('长度不足头部：直接拒绝', () {
      expect(
        () => BleFrame.decode(const <int>[1, 2, 3]),
        throwsA(isA<FrameException>().having((e) => e.message, 'message', contains('长度不足'))),
      );
    });

    test('Version 错误：设备发送正确 CRC 但错误 Version 的帧', () {
      final bytes = rawFrame(version: 2);

      expect(
        () => BleFrame.decode(bytes),
        throwsA(isA<FrameException>().having((e) => e.message, 'message', contains('Version'))),
      );
    });

    test('非法 Type：设备发送正确 CRC 但未注册 TYPE 的帧', () {
      final bytes = rawFrame(type: 0xEE);

      expect(
        () => BleFrame.decode(bytes),
        throwsA(isA<FrameException>().having((e) => e.message, 'message', contains('Type'))),
      );
    });

    test('Payload 超限：validate 拒绝', () {
      final frame = buildFrame(
        payload: List<int>.filled(BleFrame.maxPayloadSize + 1, 0),
      );

      expect(
        () => frame.encode(),
        throwsA(isA<FrameException>().having((e) => e.message, 'message', contains('超限'))),
      );
    });
  });

  group('SEQ 溢出 (§7.4/§7.5)', () {
    test('65535 后回绕到 0', () {
      final sequencer = FrameSequencer();
      var seq = 0;
      for (var i = 0; i <= 0xFFFF; i++) {
        seq = sequencer.next();
      }

      expect(seq, 0xFFFF);
      expect(sequencer.next(), 0, reason: '溢出后回绕到 0');
    });

    test('连续 SEQ 递增', () {
      final sequencer = FrameSequencer();
      expect(sequencer.next(), 0);
      expect(sequencer.next(), 1);
      expect(sequencer.next(), 2);
    });
  });
}
