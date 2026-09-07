import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:myhome/protocol/ble_frame.dart';
import 'package:myhome/protocol/fragment.dart';
import 'package:myhome/protocol/reliable_channel.dart';

import 'fake_ble_device.dart';

final Random _random = Random(7);

List<int> randomBytes(int length) =>
    Uint8List.fromList(List<int>.generate(length, (_) => _random.nextInt(256)));

ReliableChannel buildChannel(
  FakeBleDevice device, {
  int maxRetry = 2,
  Duration ackTimeout = const Duration(milliseconds: 60),
}) {
  final channel = ReliableChannel(
    transport: device,
    fragmenter: Fragmenter(mtu: 247),
    maxRetry: maxRetry,
    ackTimeout: ackTimeout,
  );
  channel.start();
  return channel;
}

void main() {
  test('正常 ACK 流程：send 完成并返回 MSG_ID (§9.1)', () async {
    final device = FakeBleDevice();
    final channel = buildChannel(device);

    final msgId = await channel.send(randomBytes(100));

    expect(msgId, 0); // 自动分配从 0 开始
    expect(device.writtenChunks, hasLength(1)); // 100B < 227B → 单帧单次写入
    await channel.dispose();
    await device.dispose();
  });

  test('分片消息写入且设备能重组并 ACK', () async {
    final device = FakeBleDevice();
    final channel = buildChannel(device);
    final data = randomBytes(1000); // 5 片 (maxData 227)

    await channel.send(data);

    expect(device.writtenChunks, hasLength(5));
    await channel.dispose();
    await device.dispose();
  });

  test('Window=1 串行：前一条未 ACK 前后续消息不写入 (§9.5)', () async {
    final device = FakeBleDevice()..ackDelay = const Duration(milliseconds: 150);
    // ackTimeout 必须大于 ackDelay，否则触发重发干扰计数
    final channel = buildChannel(device, ackTimeout: const Duration(seconds: 2));
    final first = channel.send(randomBytes(500)); // 3 片
    final second = channel.send(randomBytes(100)); // 1 片

    // 立即检查：只有第一条消息的 3 帧被写入
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(device.writtenChunks, hasLength(3));

    await first;
    await second;
    expect(device.writtenChunks, hasLength(4));

    // 前 3 帧属于 msgId=0，第 4 帧属于 msgId=1
    final frames = device.writtenChunks.map(BleFrame.decode).toList();
    expect(FragmentHeader.decode(frames[0].payload).msgId, 0);
    expect(FragmentHeader.decode(frames[3].payload).msgId, 1);

    await channel.dispose();
    await device.dispose();
  });

  test('ACK 丢失 → 超时重发 → 成功 (§9.2)', () async {
    final device = FakeBleDevice()..dropMessages = 2; // 前 2 次组装后不 ACK
    final channel = buildChannel(device, maxRetry: 3);

    final msgId = await channel.send(randomBytes(100));

    expect(msgId, 0);
    // 3 次发送：初始 + 2 次重发
    expect(device.writtenChunks, hasLength(3));
    await channel.dispose();
    await device.dispose();
  });

  test('重发字节完全一致 (同 SEQ，设备可去重 §7.4)', () async {
    final device = FakeBleDevice()..dropMessages = 1;
    final channel = buildChannel(device);

    await channel.send(randomBytes(100));

    expect(device.writtenChunks, hasLength(2));
    expect(device.writtenChunks[0], device.writtenChunks[1]);
    await channel.dispose();
    await device.dispose();
  });

  test('超过 maxRetry → 失败，队列继续处理后续消息', () async {
    final device = FakeBleDevice()..dropMessages = 2;
    final channel = buildChannel(device, maxRetry: 1);
    final errors = <(int, Object)>[];
    channel.onSendError = (id, e) => errors.add((id, e));

    // msgId=0: 初始 + 1 重发共 2 次都被丢 → 失败
    await expectLater(channel.send(randomBytes(100)), throwsA(isA<TimeoutException>()));
    // msgId=1: dropMessages 已耗尽 → 成功，证明队列未卡死
    final msgId = await channel.send(randomBytes(100));

    expect(msgId, 1);
    expect(errors, hasLength(1));
    await channel.dispose();
    await device.dispose();
  });

  test('NACK → 立即失败不重试', () async {
    final device = FakeBleDevice()..nackInstead = true;
    final channel = buildChannel(device, maxRetry: 3);

    await expectLater(
      channel.send(randomBytes(100)),
      throwsA(isA<StateError>().having((e) => e.message, 'message', contains('NACK'))),
    );
    expect(device.writtenChunks, hasLength(1)); // 无重发
    await channel.dispose();
    await device.dispose();
  });

  test('未知 / 迟到 ACK 被忽略', () async {
    final device = FakeBleDevice()..ackDelay = const Duration(milliseconds: 80);
    final channel = buildChannel(device);

    final future = channel.send(randomBytes(100));
    device.sendAck(999); // 未知 msgId
    device.sendAck(0); // 提前到达的 ACK

    await future; // 真正的 ACK (delay 后) 完成发送
    await channel.dispose();
    await device.dispose();
  });

  test('设备 → App：分片消息经字节流重组 (双向通信)', () async {
    final device = FakeBleDevice();
    final channel = buildChannel(device);
    final data = randomBytes(3000);

    final received = channel.messages.first;
    device.sendToApp(data);

    final message = await received.timeout(const Duration(seconds: 2));
    expect(message.data, data);
    expect(message.frameType, FrameType.command);
    await channel.dispose();
    await device.dispose();
  });

  test('设备断开时 send 失败', () async {
    final device = FakeBleDevice()..connected = false;
    final channel = buildChannel(device);

    await expectLater(
      channel.send(randomBytes(10)),
      throwsA(isA<StateError>()),
    );
    await channel.dispose();
    await device.dispose();
  });
}
