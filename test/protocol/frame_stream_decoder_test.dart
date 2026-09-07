import 'package:flutter_test/flutter_test.dart';

import 'package:myhome/protocol/ble_frame.dart';
import 'package:myhome/protocol/crc16.dart';
import 'package:myhome/protocol/frame_stream_decoder.dart';

BleFrame frame(int marker, {int type = FrameType.command}) => BleFrame(
      version: BleFrame.currentVersion,
      type: type,
      flags: 0,
      sequence: marker,
      payload: <int>[marker, marker, marker],
    );

void main() {
  test('单帧整块到达', () {
    final decoder = FrameStreamDecoder();
    final frames = <BleFrame>[];
    decoder.onFrame = frames.add;

    decoder.add(frame(1).encode());

    expect(frames, hasLength(1));
    expect(frames.single.sequence, 1);
  });

  test('半包：一帧拆成任意多段到达', () {
    final bytes = frame(2).encode();
    for (var split = 1; split < bytes.length; split++) {
      final decoder = FrameStreamDecoder();
      final frames = <BleFrame>[];
      decoder.onFrame = frames.add;

      decoder.add(bytes.sublist(0, split));
      decoder.add(bytes.sublist(split));

      expect(frames, hasLength(1), reason: 'split@$split');
      expect(frames.single.sequence, 2, reason: 'split@$split');
    }
  });

  test('粘包：一个 chunk 含多帧全部解出', () {
    final decoder = FrameStreamDecoder();
    final frames = <BleFrame>[];
    decoder.onFrame = frames.add;

    final chunk = <int>[
      ...frame(1).encode(),
      ...frame(2).encode(),
      ...frame(3).encode(),
    ];
    decoder.add(chunk);

    expect(frames.map((f) => f.sequence), <int>[1, 2, 3]);
  });

  test('空 chunk 无副作用', () {
    final decoder = FrameStreamDecoder();
    var count = 0;
    decoder.onFrame = (_) => count++;

    decoder.add(const <int>[]);

    expect(count, 0);
    expect(decoder.buffered, 0);
  });

  test('坏帧 (CRC) 按声明长度跳过，后续好帧仍被解出', () {
    final decoder = FrameStreamDecoder();
    final frames = <BleFrame>[];
    final errors = <String>[];
    decoder.onFrame = frames.add;
    decoder.onError = (_, reason) => errors.add(reason);

    final bad = frame(0xEE).encode();
    bad[bad.length - 1] ^= 0xFF; // 破坏 CRC
    final good = frame(7).encode();
    decoder.add(<int>[...bad, ...good]);

    expect(frames, hasLength(1));
    expect(frames.single.sequence, 7, reason: '坏帧之后的好帧仍可解析');
    expect(errors.single, contains('CRC'));
    expect(decoder.buffered, 0);
  });

  test('校验失败 (非法 Type 但 CRC 合法) → onError', () {
    final bytes = frame(1).encode();
    bytes[1] = 0xEE; // 非法 Type
    // 重算 CRC (模拟设备发出"合法 CRC 的坏字段帧")
    final body = bytes.sublist(0, bytes.length - 2);
    final crc = crc16Ccitt(body);
    bytes[bytes.length - 2] = (crc >> 8) & 0xFF;
    bytes[bytes.length - 1] = crc & 0xFF;

    final decoder = FrameStreamDecoder();
    final errors = <String>[];
    final frames = <BleFrame>[];
    decoder.onError = (_, reason) => errors.add(reason);
    decoder.onFrame = frames.add;

    decoder.add(bytes);

    expect(frames, isEmpty);
    expect(errors.single, contains('Type'));
  });

  test('声明超大 LENGTH 时保持缓冲等待 (不误解析)', () {
    final decoder = FrameStreamDecoder();
    var count = 0;
    decoder.onFrame = (_) => count++;

    decoder.add(const <int>[1, 1, 0, 0, 0, 0xFF, 0xFF, 1, 2, 3]);

    expect(count, 0);
    expect(decoder.buffered, 10);
  });
}
