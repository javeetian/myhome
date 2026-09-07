import 'dart:async';

import '../ble/ble_transport.dart';
import '../protocol/codec.dart';
import '../protocol/fragment.dart';
import '../protocol/json_codec.dart';
import '../protocol/protocol_messages.dart';
import '../protocol/reliable_channel.dart';

/// 设备客户端 (WORK_V2 §11)：Flutter 业务层与设备之间的统一入口。
///
/// 分层 (§11.3)：
/// ```text
/// 业务层 → DeviceClient → ReliableChannel → BleTransport → Plugin
/// ```
/// 本类不 import 任何 BLE Plugin，只依赖 [BleTransport] 抽象；
/// 也不知晓 HTML / WebView / DOM (§11.2)，只处理
/// Command / Response / Event / State / Patch。
///
/// 语义约定：
///   command() 返回设备的业务响应 (status='error' 也正常返回，由调用方判断)；
///   传输层失败 (ACK 超时 / NACK / 断开) 与响应超时抛异常。
///   getState() 返回最近一次缓存的设备状态 (Phase 11 才引入主动拉取)。
class DeviceClient {
  DeviceClient({
    required BleTransport transport,
    required String deviceId,
    MessageCodec codec = const JsonCodec(),
    int mtu = 247,
    int maxRetry = 3,
    Duration ackTimeout = const Duration(seconds: 2),
    Duration assembleTimeout = const Duration(seconds: 5),
    this.commandTimeout = const Duration(seconds: 8),
  })  : _deviceId = deviceId,
        _codec = codec,
        _channel = ReliableChannel(
          transport: transport,
          fragmenter: Fragmenter(mtu: mtu),
          maxRetry: maxRetry,
          ackTimeout: ackTimeout,
          assembleTimeout: assembleTimeout,
        ) {
    _channel.onSendError = (msgId, error) {
      onSendError?.call(msgId, error);
    };
  }

  final String _deviceId;
  final MessageCodec _codec;
  final ReliableChannel _channel;

  /// 命令响应超时 (设备 ACK 后迟迟不回业务响应)。
  final Duration commandTimeout;

  final Map<int, Completer<DeviceResponse>> _pending =
      <int, Completer<DeviceResponse>>{};
  final StreamController<DeviceEvent> _events =
      StreamController<DeviceEvent>.broadcast();
  final StreamController<DevicePatch> _patches =
      StreamController<DevicePatch>.broadcast();
  final StreamController<DeviceState> _states =
      StreamController<DeviceState>.broadcast();

  int _nextRequestId = 1;
  bool _connected = false;
  DeviceState? _currentState;

  /// 设备事件流 (§10.4)。
  Stream<DeviceEvent> get events => _events.stream;

  /// 状态补丁流 (§16.3)。
  Stream<DevicePatch> get patches => _patches.stream;

  /// 状态流 (Phase 11 完整实现)。
  Stream<DeviceState> get states => _states.stream;

  /// 传输层发送失败回调 (msgId, 错误)。
  void Function(int msgId, Object error)? onSendError;

  bool get isConnected => _connected;

  /// 连接设备并开始收发 (§11.1)。
  Future<void> connect() async {
    _channel.start(); // 先订阅通知流，避免丢失早期帧
    await _channel.transport.connect(_deviceId);
    _connected = true;
    _channel.messages.listen(_onIncomingMessage);
  }

  /// 断开并失败所有进行中的命令。
  Future<void> disconnect() async {
    _connected = false;
    _failAllPending(StateError('设备已断开'));
    await _channel.transport.disconnect();
  }

  void _onIncomingMessage(IncomingMessage message) {
    ProtocolMessage decoded;
    try {
      decoded = _codec.decode(message.frameType, message.data);
    } on ProtocolException {
      return; // 坏消息丢弃 (协议层已做校验，此为兜底)
    }
    switch (decoded) {
      case DeviceResponse response:
        final pending = _pending.remove(response.requestId);
        if (pending != null && !pending.isCompleted) {
          pending.complete(response);
        }
        // 未知 request_id 的响应：忽略
      case DeviceEvent event:
        if (!_events.isClosed) {
          _events.add(event);
        }
      case DevicePatch patch:
        if (!_patches.isClosed) {
          _patches.add(patch);
        }
      case DeviceState state:
        _currentState = state;
        if (!_states.isClosed) {
          _states.add(state);
        }
      case DeviceCommand _:
        // 设备不应主动发命令 (MVP 忽略)
        break;
    }
  }

  /// 发送命令并等待业务响应 (§11.1)。
  ///
  /// 业务错误 (status='error') 作为正常返回值；传输失败 / 响应超时抛异常。
  Future<DeviceResponse> command(String cmd, Map<String, dynamic> params) async {
    if (!_connected) {
      throw StateError('未连接');
    }
    final requestId = _nextRequestId++;
    final completer = Completer<DeviceResponse>();
    _pending[requestId] = completer;
    try {
      await _channel.send(
        _codec.encode(DeviceCommand(requestId: requestId, cmd: cmd, params: params)),
      );
    } catch (_) {
      _pending.remove(requestId);
      rethrow;
    }
    return completer.future.timeout(
      commandTimeout,
      onTimeout: () {
        _pending.remove(requestId);
        throw TimeoutException('命令响应超时 (request_id=$requestId, cmd=$cmd)');
      },
    );
  }

  /// 最近一次缓存的设备状态；未收到过则抛 [StateError]。
  /// (主动拉取 STATE 在 Phase 11 §16.6 实现)
  Future<DeviceState> getState() async {
    final state = _currentState;
    if (state == null) {
      throw StateError('尚未收到设备状态');
    }
    return state;
  }

  void _failAllPending(Object error) {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
    _pending.clear();
  }

  /// 释放全部资源。
  Future<void> dispose() async {
    _connected = false;
    _failAllPending(StateError('client disposed'));
    await _channel.dispose();
    await _events.close();
    await _patches.close();
    await _states.close();
  }
}
