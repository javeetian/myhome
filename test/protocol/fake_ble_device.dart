import 'dart:async';

import 'package:myhome/ble/ble_peripheral.dart';
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

  /// 设置后 connect 阻塞直到手动放行 (测试中间态)。
  Completer<void>? connectGate;

  /// connect 直接失败 (模拟连接异常)。
  bool rejectConnect = false;

  /// 组装完成但丢弃不 ACK 的消息数 (模拟 ACK 丢失)。
  int dropMessages = 0;

  /// 组装完成后回 NACK 而非 ACK。
  bool nackInstead = false;

  /// ACK 延迟。
  Duration ackDelay = Duration.zero;

  /// 命令处理器：收到命令后返回响应 (null = 不回复，模拟响应丢失)。
  /// 未设置时默认回 ok + echo params。
  DeviceResponse? Function(DeviceCommand command)? onCommand;

  /// HELLO 处理器 (Phase 10 §39)。null = 默认回 HELLO_ACK。
  DeviceHelloAck? Function(DeviceHello hello)? onHello;

  /// 资源处理器 (Phase 10 §27)。null = 默认回 5001 资源不存在。
  DeviceResourceResponse? Function(DeviceResourceRequest request)? onResource;

  /// STATE_REQUEST 处理器 (Phase 11 §16.5)。null = 默认回最近一次
  /// 推送过的状态 (无则 v1 空状态)。
  DeviceState? Function(DeviceStateRequest request)? onStateRequest;

  /// PING 处理器 (Phase 12)。null = 不回 PONG (模拟失联)。
  DevicePong? Function(DevicePing ping)? onPing;

  /// PING 响应延迟。
  Duration pingDelay = Duration.zero;

  /// 收到的全部 PING。
  final List<DevicePing> receivedPings = <DevicePing>[];

  /// 是否自动回复命令 (false 时完全不回复，模拟响应丢失)。
  bool autoRespond = true;

  /// 连接后是否自动推送初始状态 (Phase 11 §16.6 首次同步)。
  bool pushInitialStateOnConnect = true;

  /// HELLO 响应延迟 (测试 handshaking 中间态)。
  Duration helloDelay = Duration.zero;

  /// 初始状态推送延迟 (测试 syncingState 中间态)。
  Duration initialStateDelay = Duration.zero;

  /// STATE_REQUEST 响应延迟 (测试 syncingState 中间态)。
  Duration stateRequestDelay = Duration.zero;

  /// 收到的全部 STATE_REQUEST。
  final List<DeviceStateRequest> receivedStateRequests = <DeviceStateRequest>[];

  /// 手机写入的全部字节 (按 write 调用分块)。
  final List<List<int>> writtenChunks = <List<int>>[];

  /// 设备收到的全部命令。
  final List<DeviceCommand> receivedCommands = <DeviceCommand>[];

  final StreamController<List<int>> _notifications =
      StreamController<List<int>>.broadcast();

  final StreamController<BleConnectionState> _connectionStates =
      StreamController<BleConnectionState>.broadcast();

  /// 最近一次推送过的状态 (STATE_REQUEST 默认回复)。
  DeviceState? _lastState;

  /// 模拟设备侧断开 (广播 disconnected)：协议栈复位 (§21 新会话不继承旧状态)。
  void emitDisconnected() {
    _assembler.reset();
    _connectionStates.add(BleConnectionState.disconnected);
  }

  @override
  Stream<BleConnectionState> get connectionStates => _connectionStates.stream;

  final FrameStreamDecoder _decoder = FrameStreamDecoder();
  final FragmentAssembler _assembler = FragmentAssembler();
  final FrameSequencer _sequencer = FrameSequencer();
  final JsonCodec _codec = const JsonCodec();

  int _nextMsgId = 1000;

  FakeBleDevice() {
    _decoder.onFrame = _onFrame;
    _assembler.onComplete = _onMessageAssembled;
    // 重复帧 (发送端重发) → 重发 ACK (§7.4 去重语义)；dropMessages 同样抑制
    _assembler.onDuplicate = (msgId) {
      if (dropMessages > 0) {
        dropMessages--;
        return;
      }
      sendAck(msgId);
    };
  }

  void _onFrame(BleFrame frame) {
    _assembler.add(frame);
  }

  void _onMessageAssembled(int msgId, int frameType, List<int> message) {
    if (dropMessages > 0) {
      dropMessages--;
      return;
    }
    // 协议处理 (坏消息忽略，不崩)
    try {
      switch (frameType) {
        case FrameType.command:
          if (!autoRespond) {
            break;
          }
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
        case FrameType.hello:
          final hello = _codec.decode(frameType, message) as DeviceHello;
          final handler = onHello;
          final ack = handler == null
              ? DeviceHelloAck(
                  requestId: hello.requestId,
                  protocolVersion: 1,
                  deviceType: 'fake',
                  deviceModel: 'test',
                  firmwareVersion: '0.0.1',
                  uiVersion: '0.0.0',
                )
              : handler(hello);
          if (ack != null) {
            void reply() => sendMessage(FrameType.helloAck, _codec.encode(ack));
            if (helloDelay == Duration.zero) {
              reply();
            } else {
              Future<void>.delayed(helloDelay, () {
                if (!_notifications.isClosed) {
                  reply();
                }
              });
            }
          }
        case FrameType.stateRequest:
          final request = _codec.decode(frameType, message) as DeviceStateRequest;
          receivedStateRequests.add(request);
          final handler = onStateRequest;
          final state = handler == null
              ? (_lastState ?? const DeviceState(version: 1, state: <String, dynamic>{}))
              : handler(request);
          if (state != null) {
            void reply() => sendState(state.version, state.state);
            if (stateRequestDelay == Duration.zero) {
              reply();
            } else {
              Future<void>.delayed(stateRequestDelay, () {
                if (!_notifications.isClosed) {
                  reply();
                }
              });
            }
          }
        case FrameType.resourceRequest:
          final request = _codec.decode(frameType, message) as DeviceResourceRequest;
          final response = onResource?.call(request) ??
              DeviceResourceResponse(
                requestId: request.requestId,
                status: 'error',
                error: const DeviceError(code: 5001, message: 'resource not found'),
              );
          sendMessage(FrameType.resourceResponse, _codec.encode(response));
        case FrameType.ping:
          final ping = _codec.decode(frameType, message) as DevicePing;
          receivedPings.add(ping);
          final handler = onPing;
          final pong =
              handler == null ? DevicePong(requestId: ping.requestId) : handler(ping);
          if (pong != null) {
            void reply() => sendMessage(FrameType.pong, _codec.encode(pong));
            if (pingDelay == Duration.zero) {
              reply();
            } else {
              Future<void>.delayed(pingDelay, () {
                if (!_notifications.isClosed) {
                  reply();
                }
              });
            }
          }
        default:
          break;
      }
    } on ProtocolException {
      // 非协议字节 (如 channel 层的裸数据测试)：不回复业务响应
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

  void sendState(int version, Map<String, dynamic> state) {
    _lastState = DeviceState(version: version, state: state);
    sendMessage(FrameType.state, _codec.encode(_lastState!));
  }

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
    final gate = connectGate;
    if (gate != null) {
      await gate.future;
    }
    if (rejectConnect) {
      throw StateError('连接被拒绝');
    }
    connected = true;
    if (pushInitialStateOnConnect) {
      Future<void>.delayed(initialStateDelay, () {
        // 已推送过脚本化状态时不覆盖 (模拟真实设备行为)
        if (!_notifications.isClosed && connected && _lastState == null) {
          sendState(1, const <String, dynamic>{});
        }
      });
    }
  }

  @override
  Future<void> disconnect() async {
    connected = false;
    // 会话重置：新会话的 MSG_ID 不得被旧会话完成记录误判为重复 (§21)
    _assembler.reset();
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
