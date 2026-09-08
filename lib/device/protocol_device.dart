import 'dart:async';
import 'dart:typed_data';

import '../ble/ble_peripheral.dart';
import '../ble/ble_transport.dart';
import '../protocol/ble_frame.dart';
import '../protocol/fragment.dart';
import '../protocol/frame_sequencer.dart';
import '../protocol/frame_stream_decoder.dart';
import '../protocol/json_codec.dart';
import '../protocol/protocol_messages.dart';

/// 协议设备基类 (WORK_V3 §4 核心原则的代码级体现)：
/// **真实设备与模拟设备共享同一套协议行为**。
///
/// 基类处理：
///   Frame 解码 / 分片重组 / 传输层 ACK / HELLO → HELLO_ACK /
///   RESOURCE_REQUEST → 资源字节 / STATE_REQUEST → 当前状态 / PING → PONG
///
/// 子类只实现设备信息与业务命令（Device Logic + Hardware 的边界在子类）。
/// 模拟设备 (VirtualLight) 与未来真实设备固件 (C 移植) 均以此行为规范为准。
abstract class ProtocolDevice implements BleTransport {
  // ---- 子类提供 ----

  /// 设备标识 (会话用)。
  String get deviceId;

  /// 展示名称。
  String get name;

  /// UI 版本 (缓存键)。
  String get uiVersion;

  /// HELLO_ACK 内容：设备类型 / 型号 / 固件版本 / 能力。
  DeviceHelloAck helloAckFor(DeviceHello hello);

  /// 连接建立后的设备行为 (如推送初始状态)。
  Future<void> onDeviceConnect();

  /// 断开时的设备行为 (如停止传感器定时器)。
  Future<void> onDeviceDisconnect();

  /// 当前状态快照 (STATE_REQUEST 回复与初始推送)。
  DeviceState get currentState;

  /// 业务命令处理：返回响应 (null = 不回复)。
  Future<DeviceResponse?> handleCommand(DeviceCommand command);

  /// 资源内容 (manifest.json / ui.pkg 等)；null = 资源不存在。
  Uint8List? resourceBytes(String path);

  // ---- 协议栈 ----

  final StreamController<List<int>> _notifications =
      StreamController<List<int>>.broadcast();
  final StreamController<BleConnectionState> _connectionStates =
      StreamController<BleConnectionState>.broadcast();

  final FrameStreamDecoder _decoder = FrameStreamDecoder();
  final FragmentAssembler _assembler = FragmentAssembler();
  final FrameSequencer _sequencer = FrameSequencer();
  final JsonCodec _codec = const JsonCodec();

  int _nextMsgId = 1000;
  bool _connected = false;

  ProtocolDevice() {
    _decoder.onFrame = (frame) => _assembler.add(frame);
    _assembler.onComplete = _onMessageAssembled;
  }

  void _onMessageAssembled(int msgId, int frameType, List<int> message) {
    switch (frameType) {
      case FrameType.command:
        unawaited(_handleCommandFrame(message));
      case FrameType.hello:
        try {
          final hello = _codec.decode(frameType, message) as DeviceHello;
          sendMessage(FrameType.helloAck, _codec.encode(helloAckFor(hello)));
        } on ProtocolException {
          // 坏握手请求：忽略
        }
      case FrameType.resourceRequest:
        try {
          final request =
              _codec.decode(frameType, message) as DeviceResourceRequest;
          final bytes = resourceBytes(request.path);
          final response = bytes == null
              ? DeviceResourceResponse(
                  requestId: request.requestId,
                  status: 'error',
                  error: const DeviceError(
                      code: 5001, message: 'resource not found'),
                )
              : DeviceResourceResponse(
                  requestId: request.requestId, data: bytes);
          sendMessage(
              FrameType.resourceResponse, _codec.encode(response));
        } on ProtocolException {
          // 坏资源请求：忽略
        }
      case FrameType.stateRequest:
        try {
          // 全量状态请求 (§16.5/§16.6)：回复当前状态快照 (不递增版本)
          final state = currentState;
          sendMessage(FrameType.state, _codec.encode(state));
        } on ProtocolException {
          // 坏状态请求：忽略
        }
      case FrameType.ping:
        try {
          final ping = _codec.decode(frameType, message) as DevicePing;
          sendMessage(
              FrameType.pong, _codec.encode(DevicePong(requestId: ping.requestId)));
        } on ProtocolException {
          // 坏 PING：忽略
        }
      default:
        break;
    }
    // 传输层 ACK (所有消息)
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

  Future<void> _handleCommandFrame(List<int> message) async {
    final DeviceCommand command;
    try {
      command = _codec.decode(FrameType.command, message) as DeviceCommand;
    } on ProtocolException {
      return; // 坏命令：忽略
    }
    final response = await handleCommand(command);
    if (response != null) {
      sendMessage(FrameType.response, _codec.encode(response));
    }
  }

  // ---- 子类可用：设备 → App 发送 ----

  /// 发送一条 (自动分片的) 协议消息。
  void sendMessage(int frameType, List<int> data) {
    final fragmenter = Fragmenter(
      mtu: 247,
      frameType: frameType,
      sequencer: _sequencer,
    );
    for (final frame in fragmenter.fragment(_nextMsgId++, data)) {
      _notifications.add(frame.encode());
    }
  }

  /// 推送全量状态。
  void pushState(DeviceState state) =>
      sendMessage(FrameType.state, _codec.encode(state));

  /// 推送事件。
  void sendEvent(String event, Map<String, dynamic> data) => sendMessage(
        FrameType.event,
        _codec.encode(DeviceEvent(event: event, data: data)),
      );

  // ---- BleTransport (回环侧) ----

  @override
  Future<void> connect(String deviceId) async {
    _connected = true;
    await onDeviceConnect();
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    await onDeviceDisconnect();
  }

  @override
  Future<void> write(List<int> data) async {
    if (!_connected) {
      throw StateError('设备已断开');
    }
    _decoder.add(data);
  }

  @override
  Stream<List<int>> get notifications => _notifications.stream;

  @override
  Stream<BleConnectionState> get connectionStates => _connectionStates.stream;

  @override
  Future<int> requestMtu(int mtu) async => mtu.clamp(23, 247);

  /// 释放资源。
  Future<void> dispose() async {
    await disconnect();
    _assembler.dispose();
    await _notifications.close();
  }
}
