import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:myhome/protocol/ble_frame.dart';
import 'package:myhome/protocol/fragment.dart';

final Random _random = Random(42);

List<int> randomBytes(int length) =>
    Uint8List.fromList(List<int>.generate(length, (_) => _random.nextInt(256)));

/// 手工构造含 Fragment 头的帧 (可造坏字段)。
BleFrame fragFrame({
  int msgId = 1,
  int index = 0,
  int total = 1,
  int? length, // null → 与实际 data 长度一致
  List<int> data = const <int>[0xaa, 0xbb],
  int sequence = 0,
}) {
  final actual = length ?? data.length;
  final header = FragmentHeader(
    msgId: msgId,
    index: index,
    total: total,
    length: actual,
  );
  return BleFrame(
    version: BleFrame.currentVersion,
    type: FrameType.command,
    flags: 0,
    sequence: sequence,
    payload: <int>[...header.encode(), ...data],
  );
}

void main() {
  group('Fragmenter (发送方向 §8.3)', () {
    test('MTU 过小抛出 FragmentException', () {
      final fragmenter = Fragmenter(mtu: 19);
      expect(() => fragmenter.fragment(1, <int>[1, 2, 3]), throwsA(isA<FragmentException>()));
    });

    test('单 Fragment 消息: TOTAL=1 且数据完整', () {
      final fragmenter = Fragmenter(mtu: 247);
      final data = randomBytes(100);

      final frames = fragmenter.fragment(7, data);
      expect(frames, hasLength(1));

      final header = FragmentHeader.decode(frames.single.payload);
      expect(header.msgId, 7);
      expect(header.index, 0);
      expect(header.total, 1);
      expect(header.length, 100);
      expect(frames.single.payload.sublist(FragmentHeader.size), data);
    });

    test('空消息: 产生 1 个 TOTAL=1 / LENGTH=0 的 Fragment', () {
      final fragmenter = Fragmenter(mtu: 247);
      final frames = fragmenter.fragment(3, const <int>[]);

      expect(frames, hasLength(1));
      final header = FragmentHeader.decode(frames.single.payload);
      expect(header.total, 1);
      expect(header.length, 0);
    });

    test('SEQ 跨分片连续分配 (§7.4)', () {
      final fragmenter = Fragmenter(mtu: 40);
      // maxDataSize = 40-3-7-8-2 = 20 → 100 字节 → 5 片
      final frames = fragmenter.fragment(1, randomBytes(100));

      expect(frames, hasLength(5));
      expect(frames.map((f) => f.sequence).toList(), <int>[0, 1, 2, 3, 4]);
    });

    test('每片长度不超过 maxDataSize，且拼接还原', () {
      final fragmenter = Fragmenter(mtu: 40);
      final data = randomBytes(100);
      final frames = fragmenter.fragment(1, data);

      for (final frame in frames) {
        final header = FragmentHeader.decode(frame.payload);
        expect(header.length, lessThanOrEqualTo(fragmenter.maxDataSize));
      }
      final joined = frames.expand((f) => f.payload.sublist(FragmentHeader.size)).toList();
      expect(joined, data);
    });
  });

  group('Assembler (接收方向 §8.4 / 大小矩阵 §8.7)', () {
    for (final size in <int>[100, 500, 1000, 5000, 10000, 50000]) {
      test('$size 字节完整往返', () async {
        final data = randomBytes(size);
        final fragmenter = Fragmenter(mtu: 247);
        final assembler = FragmentAssembler();
        final completed = <List<int>>[];

        assembler.onComplete = (_, msg) => completed.add(msg);
        for (final frame in fragmenter.fragment(42, data)) {
          assembler.add(frame);
        }

        expect(completed, hasLength(1));
        expect(completed.single, data);
        assembler.dispose();
      });
    }

    test('乱序接收: 任意顺序到达均正确重组', () {
      final data = randomBytes(1000);
      final frames = Fragmenter(mtu: 100).fragment(1, data);
      final shuffled = List<BleFrame>.of(frames)..shuffle(_random);
      final assembler = FragmentAssembler();
      final completed = <List<int>>[];

      assembler.onComplete = (_, msg) => completed.add(msg);
      for (final frame in shuffled) {
        assembler.add(frame);
      }

      expect(completed, hasLength(1));
      expect(completed.single, data);
      assembler.dispose();
    });

    test('多消息交错: 两个 MSG_ID 交替到达均正确完成', () {
      final a = randomBytes(500);
      final b = randomBytes(700);
      final framesA = Fragmenter(mtu: 100).fragment(1, a);
      final framesB = Fragmenter(mtu: 100).fragment(2, b);
      final assembler = FragmentAssembler();
      final completed = <int, List<int>>{};

      assembler.onComplete = (id, msg) => completed[id] = msg;
      final interleaved = <BleFrame>[];
      for (var i = 0; i < max(framesA.length, framesB.length); i++) {
        if (i < framesA.length) interleaved.add(framesA[i]);
        if (i < framesB.length) interleaved.add(framesB[i]);
      }
      for (final frame in interleaved) {
        assembler.add(frame);
      }

      expect(completed[1], a);
      expect(completed[2], b);
      assembler.dispose();
    });

    test('重复 Fragment: 忽略重复，正常完成', () {
      final data = randomBytes(300);
      final frames = Fragmenter(mtu: 100).fragment(1, data);
      final assembler = FragmentAssembler();
      final completed = <List<int>>[];
      final discarded = <String>[];

      assembler.onComplete = (_, msg) => completed.add(msg);
      assembler.onDiscard = (_, reason) => discarded.add(reason);
      assembler.add(frames[0]);
      assembler.add(frames[0]); // 重复
      for (var i = 1; i < frames.length; i++) {
        assembler.add(frames[i]);
      }

      expect(completed, hasLength(1));
      expect(completed.single, data);
      expect(discarded, isEmpty);
      assembler.dispose();
    });
  });

  group('Assembler 异常处理 (§8.5)', () {
    test('缺 Fragment: 活动超时丢弃整个消息 (§8.6)', () async {
      final data = randomBytes(300);
      final frames = Fragmenter(mtu: 100).fragment(1, data); // 3 片
      final assembler = FragmentAssembler(timeout: const Duration(milliseconds: 50));
      final discarded = <(int?, String)>[];

      assembler.onDiscard = (id, reason) => discarded.add((id, reason));
      assembler.add(frames[0]);
      assembler.add(frames[1]);
      // 缺 frames[2] → 等待超时
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(discarded, <(int?, String)>[(1, '超时')]);
      assembler.dispose();
    });

    test('超时丢弃后同 MSG_ID 可以重新开始组装', () async {
      final assembler = FragmentAssembler(timeout: const Duration(milliseconds: 50));
      final completed = <List<int>>[];
      assembler.onComplete = (_, msg) => completed.add(msg);

      assembler.add(fragFrame(msgId: 9, index: 0, total: 2, data: <int>[1]));
      await Future<void>.delayed(const Duration(milliseconds: 120)); // 超时丢弃
      // 重新发送完整两片
      assembler.add(fragFrame(msgId: 9, index: 0, total: 2, data: <int>[1]));
      assembler.add(fragFrame(msgId: 9, index: 1, total: 2, data: <int>[2]));

      expect(completed.single, <int>[1, 2]);
      assembler.dispose();
    });

    test('错误 TOTAL: 后续分片 TOTAL 不一致 → 丢弃', () {
      final assembler = FragmentAssembler();
      final discarded = <(int?, String)>[];
      assembler.onDiscard = (id, reason) => discarded.add((id, reason));

      assembler.add(fragFrame(msgId: 1, index: 0, total: 3, data: <int>[1]));
      assembler.add(fragFrame(msgId: 1, index: 1, total: 4, data: <int>[2])); // 不一致

      expect(discarded, <(int?, String)>[(1, '错误 TOTAL')]);
      assembler.dispose();
    });

    test('错误 LENGTH: 头声明与实际不符 → 丢弃', () {
      final assembler = FragmentAssembler();
      final discarded = <(int?, String)>[];
      assembler.onDiscard = (id, reason) => discarded.add((id, reason));

      assembler.add(fragFrame(msgId: 1, index: 0, total: 2, length: 99, data: <int>[1]));

      expect(discarded, <(int?, String)>[(1, '错误 LENGTH')]);
      assembler.dispose();
    });

    test('INDEX 越界: index >= total → 丢弃', () {
      final assembler = FragmentAssembler();
      final discarded = <(int?, String)>[];
      assembler.onDiscard = (id, reason) => discarded.add((id, reason));

      assembler.add(fragFrame(msgId: 1, index: 2, total: 2, data: <int>[1]));

      expect(discarded, <(int?, String)>[(1, 'INDEX 越界')]);
      assembler.dispose();
    });

    test('Payload 短于 Fragment 头 → 丢弃 (msgId=null)', () {
      final assembler = FragmentAssembler();
      final discarded = <(int?, String)>[];
      assembler.onDiscard = (id, reason) => discarded.add((id, reason));

      assembler.add(
        BleFrame(
          version: BleFrame.currentVersion,
          type: FrameType.command,
          flags: 0,
          sequence: 0,
          payload: const <int>[1, 2, 3], // < 8 字节
        ),
      );

      expect(discarded, <(int?, String)>[(null, '长度不足')]);
      assembler.dispose();
    });
  });
}
