import 'dart:async';

import 'package:myhome/ble/ble_transport.dart';
import 'package:myhome/protocol/ble_frame.dart';
import 'package:myhome/protocol/fragment.dart';
import 'package:myhome/protocol/frame_sequencer.dart';
import 'package:myhome/protocol/frame_stream_decoder.dart';
import 'package:myhome/protocol/json_codec.dart';
import 'package:myhome/protocol/protocol_messages.dart';

/// 脚本化假 BLE 设备：复用本项目自己的解码/组装/协议逻辑 (dogfooding)，
/// 可编程模拟 ACK 丢失 / 延迟 / NACK / 协议响应，用于 Phase 4+ 测试。
class FakeBleDevice implements BleTransport {
  /// 是否连接 (false 时 write 抛错，模拟断开)。
  bool connected = true;

  /// 组装完成但丢弃不 ACK 的消息数 (模拟 ACK 丢失)。
  int dropMessages = 0;

  /// 组装完成后回 NACK 而非 ACK。
  bool nackInstead = false;

  /// ACK 延迟。
  Duration ackDelay = Duration.zero;

  /// 命令处理器：收到命令后返回响应 (null = 不回复，模拟响应丢失)。
  /// 未设置时默认回 ok + echo params。
  DeviceResponse? Function(DeviceCommand command)? onCommand;

  /// 是否自动回复命令 (false 时完全不回复，模拟响应丢失)。
  bool autoRespond = true;

  /// 手机写入的全部字节 (按 write 调用分块)。
  final List<List<int>> writtenChunks = <List<int>>[];

  /// 设备收到的全部命令。
  final List<DeviceCommand> receivedCommands = <DeviceCommand>[];

  final StreamController<List<int>> _notifications =
      StreamController<List<int>>.broadcast();

  final FrameStreamDecoder _decoder = FrameStreamDecoder();
  final FragmentAssembler _assembler = FragmentAssembler();
  final FrameSequencer _sequencer = FrameSequencer();
  final JsonCodec _codec = const JsonCodec();

  int _nextMsgId = 1000;

  FakeBleDevice() {
    _decoder.onFrame = _onFrame;
    _assembler.onComplete = _onMessageAssembled;
  }

  void _onFrame(BleFrame frame) {
    _assembler.add(frame);
  }

  void _onMessageAssembled(int msgId, int frameType, List<int> message) {
    if (dropMessages > 0) {
      dropMessages--;
      return;
    }
    // 协议处理：命令 → 脚本化响应 (坏消息忽略，不崩)
    if (frameType == FrameType.command && autoRespond) {
      try {
        final command = _codec.decode(frameType, message) as DeviceCommand;
        receivedCommands.add(command);
        final handler = onCommand;
        final response = handler == null
            ? DeviceResponse(
                requestId: command.requestId,
                data: <String, dynamic>{'echo': command.params},
              )
            : handler(command);
        if (response != null) {
          sendMessage(FrameType.response, _codec.encode(response));
        }
      } on ProtocolException {
        // 非协议字节 (如 channel 层的裸数据测试)：不回复业务响应
      }
    }
    // 传输层 ACK (所有消息)
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

  /// 设备 → App：发送一条 (自动分片的) 协议消息。
  void sendMessage(int frameType, List<int> data) {
    final fragmenter = Fragmenter(mtu: 247, frameType: frameType, sequencer: _sequencer);
    for (final frame in fragmenter.fragment(_nextMsgId++, data)) {
      _notifications.add(frame.encode());
    }
  }

  /// 设备 → App：发送裸数据消息 (兼容旧测试)。
  void sendToApp(List<int> data) => sendMessage(FrameType.command, data);

  /// 设备 → App：发送事件 / 状态 / 补丁。
  void sendEvent(String event, Map<String, dynamic> data) =>
      sendMessage(FrameType.event, _codec.encode(DeviceEvent(event: event, data: data)));

  void sendState(int version, Map<String, dynamic> state) =>
      sendMessage(FrameType.state, _codec.encode(DeviceState(version: version, state: state)));

  void sendPatch(int version, List<Map<String, dynamic>> ops) =>
      sendMessage(FrameType.patch, _codec.encode(DevicePatch(version: version, ops: ops)));

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
