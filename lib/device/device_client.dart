import 'dart:async';

import '../ble/ble_transport.dart';
import '../core/app_log.dart';
import '../core/device_stats.dart';
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
    this.resourceTimeout = const Duration(seconds: 60),
    DeviceStats? stats,
    AppLog? log,
  })  : _deviceId = deviceId,
        _codec = codec,
        stats = stats ?? DeviceStats(),
        log = log ?? AppLog.instance,
        _channel = ReliableChannel(
          transport: transport,
          fragmenter: Fragmenter(mtu: mtu),
          maxRetry: maxRetry,
          ackTimeout: ackTimeout,
          assembleTimeout: assembleTimeout,
          stats: stats,
          log: log,
        ) {
    _channel.onSendError = (msgId, error) {
      onSendError?.call(msgId, error);
    };
  }

  final String _deviceId;
  final MessageCodec _codec;
  final ReliableChannel _channel;

  /// 通信统计 (Phase 12 §28/§33)。
  final DeviceStats stats;

  /// 日志 (Phase 12 §31)。
  final AppLog log;

  /// 设备标识 (UI Adapter 的 /api/device 使用)。
  String get deviceId => _deviceId;

  /// 最近一次 HELLO_ACK (握手结果, §39)。
  DeviceHelloAck? get helloAck => _helloAck;

  /// 心跳失联回调 (连续多次无 PONG 触发, Phase 12 §22 扩展)。
  /// 由会话层接入断线流程 (§20)。
  void Function()? onConnectionLost;

  Timer? _heartbeatTimer;
  Completer<void>? _pongPending;
  bool _heartbeatRunning = false;
  int _missedPongs = 0;
  int _heartbeatSeq = 0;
  int _heartbeatMissedThreshold = 3;

  /// 命令响应超时 (设备 ACK 后迟迟不回业务响应)。
  final Duration commandTimeout;

  /// 资源下载超时 (ui.pkg 可能较大, §27)。
  final Duration resourceTimeout;

  final Map<int, Completer<DeviceResponse>> _pending =
      <int, Completer<DeviceResponse>>{};
  final StreamController<DeviceEvent> _events =
      StreamController<DeviceEvent>.broadcast();
  final StreamController<DevicePatch> _patches =
      StreamController<DevicePatch>.broadcast();
  final StreamController<DeviceState> _states =
      StreamController<DeviceState>.broadcast();

  /// 进行中的握手 (MVP 同一时刻只允许一次, §39)。
  Completer<DeviceHelloAck>? _helloPending;

  /// 进行中的资源请求 (大文件串行, §27)。
  Completer<DeviceResourceResponse>? _resourcePending;

  int _nextRequestId = 1;
  bool _connected = false;
  int _stateVersion = 0;
  Map<String, dynamic> _stateMap = <String, dynamic>{};
  Completer<DeviceState>? _statePending;
  DeviceHelloAck? _helloAck;

  /// 最近缓存的设备状态 (Phase 11 §16)；未同步过为 null。
  DeviceState? get currentState => _stateVersion == 0
      ? null
      : DeviceState(
          version: _stateVersion,
          state: Map<String, dynamic>.unmodifiable(_stateMap),
        );

  /// 是否已收到过设备状态。
  bool get hasState => _stateVersion > 0;

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
    stats.markConnected();
    log.info('DEVICE', '已连接', deviceId: _deviceId);
    _channel.messages.listen(_onIncomingMessage);
  }

  /// 断开并失败所有进行中的命令。
  /// 状态存储同步清空 (§21：重连不能直接恢复旧状态，必须重新同步)。
  Future<void> disconnect() async {
    _connected = false;
    stopHeartbeat();
    _stateVersion = 0;
    _stateMap = <String, dynamic>{};
    _failAllPending(StateError('设备已断开'));
    log.info('DEVICE', '已断开', deviceId: _deviceId);
    await _channel.transport.disconnect();
  }

  /// 启动心跳 (Phase 12 §22 扩展)：定期 PING，连续
  /// [missedThreshold] 次无 PONG → [onConnectionLost]。
  void startHeartbeat({
    Duration interval = const Duration(seconds: 10),
    int missedThreshold = 3,
  }) {
    if (_heartbeatRunning) {
      return;
    }
    _heartbeatRunning = true;
    _missedPongs = 0;
    _heartbeatMissedThreshold = missedThreshold;
    _heartbeatTimer = Timer.periodic(interval, (_) => unawaited(_sendPing()));
    unawaited(_sendPing()); // 立即发第一个
  }

  void stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _heartbeatRunning = false;
    final pending = _pongPending;
    if (pending != null && !pending.isCompleted) {
      pending.complete(); // 防悬挂
    }
    _pongPending = null;
  }

  Future<void> _sendPing() async {
    if (!_connected || !_heartbeatRunning) {
      return;
    }
    if (_pongPending != null) {
      _registerMissedPong(); // 上一次还没回
      return;
    }
    final requestId = ++_heartbeatSeq;
    final completer = Completer<void>();
    _pongPending = completer;
    final message = DevicePing(requestId: requestId);
    try {
      await _channel.send(
        _codec.encode(message),
        frameType: message.frameType,
      );
      log.trace('DEVICE', 'PING', deviceId: _deviceId, requestId: requestId);
      await completer.future.timeout(
        _heartbeatTimer == null
            ? const Duration(seconds: 5)
            : Duration(milliseconds: 200), // 心跳间隔由定时器保证，这里仅兜底
      );
      _missedPongs = 0;
    } catch (_) {
      _registerMissedPong();
    } finally {
      _pongPending = null;
    }
  }

  void _registerMissedPong() {
    _missedPongs++;
    log.warn('DEVICE', 'PONG 丢失 ($_missedPongs/$_heartbeatMissedThreshold)',
        deviceId: _deviceId);
    if (_missedPongs >= _heartbeatMissedThreshold) {
      _handleConnectionLost();
    }
  }

  void _handleConnectionLost() {
    stopHeartbeat();
    log.error('DEVICE', '心跳失联，判定设备离线', deviceId: _deviceId);
    onConnectionLost?.call();
  }

  void _onIncomingMessage(IncomingMessage message) {
    if (!_connected) {
      return; // 断线期间的迟到消息：丢弃 (§21 重连必须重新同步，不得恢复旧状态)
    }
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
        _applyPatch(patch);
      case DeviceState state:
        _applyState(state);
      case DeviceHelloAck ack:
        final pending = _helloPending;
        if (pending != null && !pending.isCompleted) {
          _helloPending = null;
          _helloAck = ack;
          pending.complete(ack);
        }
      case DeviceResourceResponse response:
        final pending = _resourcePending;
        if (pending != null && !pending.isCompleted) {
          _resourcePending = null;
          pending.complete(response);
        }
      case DeviceCommand _:
      case DeviceHello _:
      case DeviceResourceRequest _:
      case DeviceStateRequest _:
        // 设备不应主动发这些消息 (MVP 忽略)
        break;
      case DevicePing _:
        // 设备不应主动发 PING (MVP 忽略)
        break;
      case DevicePong _:
        final pending = _pongPending;
        if (pending != null && !pending.isCompleted) {
          pending.complete();
        }
        break;
    }
  }

  /// 全量状态：直接替换本地副本 (§16.1)。
  void _applyState(DeviceState state) {
    _stateMap = state.state;
    _stateVersion = state.version;
    if (!_states.isClosed) {
      _states.add(state);
    }
    final pending = _statePending;
    if (pending != null && !pending.isCompleted) {
      _statePending = null;
      pending.complete(state);
    }
  }

  /// 增量补丁：应用到本地状态副本 (§16.3)。
  /// 无基准状态 → 主动请求全量 (§16.6)；
  /// 版本跳跃 (Gap) → 应用后请求全量兜底 (§16.5)；过期补丁忽略。
  void _applyPatch(DevicePatch patch) {
    if (!_patches.isClosed) {
      _patches.add(patch);
    }
    if (_stateVersion == 0) {
      unawaited(_requestStateIfIdle()); // 无基准，等全量状态
      return;
    }
    final gap = patch.version > _stateVersion + 1;
    final stale = patch.version <= _stateVersion;
    if (!stale) {
      for (final op in patch.ops) {
        _applyPatchOp(op);
      }
      _stateVersion = patch.version;
      if (!_states.isClosed) {
        _states.add(DeviceState(
          version: _stateVersion,
          state: Map<String, dynamic>.unmodifiable(_stateMap),
        ));
      }
    }
    if (gap) {
      unawaited(_requestStateIfIdle()); // §16.5 Gap → 全量补全
    }
  }

  /// JSON Patch 子集：replace / add / remove (§16.3)。
  /// 坏操作 / 路径不存在：忽略，等待 Gap 兜底。
  void _applyPatchOp(Map<String, dynamic> op) {
    final path = op['path'];
    final opName = op['op'];
    if (path is! String || opName is! String) {
      return;
    }
    final parts = path.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) {
      return;
    }
    var cur = _stateMap;
    for (var i = 0; i < parts.length - 1; i++) {
      final next = cur[parts[i]];
      if (next is! Map<String, dynamic>) {
        return;
      }
      cur = next;
    }
    switch (opName) {
      case 'replace':
      case 'add':
        cur[parts.last] = op['value'];
      case 'remove':
        cur.remove(parts.last);
    }
  }

  /// 主动请求全量状态 (§16.5/§16.6 STATE_REQUEST)。
  /// 设备响应为下一条 STATE 消息 (单槽配对)。
  Future<DeviceState> requestState() async {
    if (!_connected) {
      throw StateError('未连接');
    }
    final existing = _statePending;
    if (existing != null) {
      return existing.future; // 已在请求中
    }
    final requestId = _nextRequestId++;
    final completer = Completer<DeviceState>();
    _statePending = completer;
    final message = DeviceStateRequest(requestId: requestId);
    try {
      await _channel.send(
        _codec.encode(message),
        frameType: message.frameType,
      );
    } catch (_) {
      _statePending = null;
      rethrow;
    }
    return completer.future.timeout(
      commandTimeout,
      onTimeout: () {
        if (identical(_statePending, completer)) {
          _statePending = null;
        }
        throw TimeoutException('状态同步超时 (request_id=$requestId)');
      },
    );
  }

  /// Gap 兜底：无进行中请求时发起全量请求。
  Future<void> _requestStateIfIdle() async {
    if (_statePending != null) {
      return;
    }
    try {
      await requestState();
    } catch (_) {
      // 补全失败：下一条 Patch/State 会再次触发 (§16.5)
    }
  }

  /// 同步设备状态 (§16.6)：已收到则返回缓存，否则主动请求。
  Future<DeviceState> syncState() async {
    final current = currentState;
    if (current != null) {
      return current;
    }
    return requestState();
  }

  /// HELLO 握手 (§39/§15.3)：返回设备 HELLO_ACK。
  Future<DeviceHelloAck> hello() async {
    if (!_connected) {
      throw StateError('未连接');
    }
    final requestId = _nextRequestId++;
    final completer = Completer<DeviceHelloAck>();
    _helloPending = completer;
    final message = DeviceHello(requestId: requestId);
    try {
      await _channel.send(
        _codec.encode(message),
        frameType: message.frameType,
      );
    } catch (_) {
      _helloPending = null;
      rethrow;
    }
    return completer.future.timeout(
      commandTimeout,
      onTimeout: () {
        throw TimeoutException('HELLO 握手超时 (request_id=$requestId)');
      },
    );
  }

  /// 请求设备资源 (§27)：如 manifest.json / ui.pkg。
  /// MVP 同一时刻只允许一个资源请求 (大文件串行)。
  Future<DeviceResourceResponse> requestResource(String path) async {
    if (!_connected) {
      throw StateError('未连接');
    }
    final requestId = _nextRequestId++;
    final completer = Completer<DeviceResourceResponse>();
    _resourcePending = completer;
    final message = DeviceResourceRequest(requestId: requestId, path: path);
    try {
      await _channel.send(
        _codec.encode(message),
        frameType: message.frameType,
      );
    } catch (_) {
      _resourcePending = null;
      rethrow;
    }
    return completer.future.timeout(
      resourceTimeout,
      onTimeout: () {
        throw TimeoutException('资源下载超时 ($path, request_id=$requestId)');
      },
    );
  }

  /// 发送命令并等待业务响应 (§11.1)。
  ///
  /// 业务错误 (status='error') 作为正常返回值；传输失败 / 响应超时抛异常。
  Future<DeviceResponse> command(String cmd, Map<String, dynamic> params) async {
    if (!_connected) {
      throw StateError('未连接');
    }
    final stopwatch = Stopwatch()..start();
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
    final response = await completer.future.timeout(
      commandTimeout,
      onTimeout: () {
        _pending.remove(requestId);
        throw TimeoutException('命令响应超时 (request_id=$requestId, cmd=$cmd)');
      },
    );
    stopwatch.stop();
    stats.recordCommandLatency(stopwatch.elapsed);
    log.debug(
      'DEVICE',
      '命令 $cmd → ${response.status} (${stopwatch.elapsedMilliseconds}ms)',
      deviceId: _deviceId,
      requestId: requestId,
    );
    return response;
  }

  /// 获取设备状态 (§16.6)：未同步过则主动请求全量。
  Future<DeviceState> getState() => syncState();

  void _failAllPending(Object error) {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
    _pending.clear();
    final hello = _helloPending;
    if (hello != null && !hello.isCompleted) {
      _helloPending = null;
      hello.completeError(error);
    }
    final resource = _resourcePending;
    if (resource != null && !resource.isCompleted) {
      _resourcePending = null;
      resource.completeError(error);
    }
    final statePending = _statePending;
    if (statePending != null && !statePending.isCompleted) {
      _statePending = null;
      statePending.completeError(error);
    }
  }

  /// 释放全部资源。
  Future<void> dispose() async {
    _connected = false;
    stopHeartbeat();
    _failAllPending(StateError('client disposed'));
    await _channel.dispose();
    await _events.close();
    await _patches.close();
    await _states.close();
  }
}
