import 'dart:async';

import 'package:myhome/ble/ble_transport.dart';
import 'package:myhome/protocol/ble_frame.dart';
import 'package:myhome/protocol/fragment.dart';
import 'package:myhome/protocol/frame_sequencer.dart';
import 'package:myhome/protocol/frame_stream_decoder.dart';

/// 脚本化假 BLE 设备：复用本项目自己的解码/组装逻辑 (dogfooding)，
/// 可编程模拟 ACK 丢失 / 延迟 / NACK，用于 Phase 4 可靠通道测试。
class FakeBleDevice implements BleTransport {
  /// 是否连接 (false 时 write 抛错，模拟断开)。
  bool connected = true;

  /// 组装完成但丢弃不 ACK 的消息数 (模拟 ACK 丢失)。
  int dropMessages = 0;

  /// 组装完成后回 NACK 而非 ACK。
  bool nackInstead = false;

  /// ACK 延迟。
  Duration ackDelay = Duration.zero;

  /// 手机写入的全部字节 (按 write 调用分块)。
  final List<List<int>> writtenChunks = <List<int>>[];

  final StreamController<List<int>> _notifications =
      StreamController<List<int>>.broadcast();

  final FrameStreamDecoder _decoder = FrameStreamDecoder();
  final FragmentAssembler _assembler = FragmentAssembler();
  final Fragmenter _fragmenter = Fragmenter(mtu: 247);
  final FrameSequencer _sequencer = FrameSequencer();

  int _nextMsgId = 1000;

  FakeBleDevice() {
    _decoder.onFrame = _onFrame;
    _assembler.onComplete = _onMessageAssembled;
  }

  void _onFrame(BleFrame frame) {
    _assembler.add(frame);
  }

  void _onMessageAssembled(int msgId, List<int> message) {
    if (dropMessages > 0) {
      dropMessages--;
      return;
    }
    final replyType = nackInstead ? FrameType.nack : FrameType.ack;
    final bytes = BleFrame(
      version: BleFrame.currentVersion,
      type: replyType,
      flags: 0,
      sequence: _sequencer.next(),
      payload: <int>[msgId >> 8, msgId & 0xFF],
    ).encode();
    Future<void>.delayed(ackDelay, () {
      if (!_notifications.isClosed) {
        _notifications.add(bytes);
      }
    });
  }

  /// 设备 → App：发送一条 (自动分片的) 消息。
  void sendToApp(List<int> message) {
    for (final frame in _fragmenter.fragment(_nextMsgId++, message)) {
      _notifications.add(frame.encode());
    }
  }

  /// 设备 → App：发送裸 ACK 帧 (测试未知/迟到 ACK)。
  void sendAck(int msgId) {
    _notifications.add(
      BleFrame(
        version: BleFrame.currentVersion,
        type: FrameType.ack,
        flags: 0,
        sequence: _sequencer.next(),
        payload: <int>[msgId >> 8, msgId & 0xFF],
      ).encode(),
    );
  }

  @override
  Future<void> connect(String deviceId) async {
    connected = true;
  }

  @override
  Future<void> disconnect() async {
    connected = false;
  }

  @override
  Future<void> write(List<int> data) async {
    if (!connected) {
      throw StateError('设备已断开');
    }
    writtenChunks.add(List<int>.of(data));
    _decoder.add(data);
  }

  @override
  Stream<List<int>> get notifications => _notifications.stream;

  @override
  Future<int> requestMtu(int mtu) async => mtu.clamp(23, 247);

  /// 释放资源。
  Future<void> dispose() async {
    _assembler.dispose();
    await _notifications.close();
  }
}
