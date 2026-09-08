import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_log.dart';
import '../device/device_client.dart';
import '../device/protocol_device.dart';
import '../protocol/protocol_messages.dart';
import '../ui_runtime/ui_cache.dart';
import '../ui_runtime/ui_server.dart';

/// Device Studio 会话状态 (WORK_V3 §22/§28)。
class StudioState {
  const StudioState({
    this.device,
    this.client,
    this.uiServer,
    this.entryUrl,
    this.currentState,
    this.helloAck,
    this.error,
    this.protocolLog = const <String>[],
  });

  final ProtocolDevice? device;
  final DeviceClient? client;
  final UiServer? uiServer;

  /// UI 预览入口 (随机端口 + token)。
  final String? entryUrl;

  /// 设备当前状态。
  final DeviceState? currentState;

  /// 握手结果 (设备信息)。
  final DeviceHelloAck? helloAck;

  final String? error;

  /// Protocol Console 日志 (§24)。
  final List<String> protocolLog;

  bool get isRunning => client != null;

  StudioState copyWith({
    DeviceState? currentState,
    List<String>? protocolLog,
  }) =>
      StudioState(
        device: device,
        client: client,
        uiServer: uiServer,
        entryUrl: entryUrl,
        currentState: currentState ?? this.currentState,
        helloAck: helloAck,
        error: error,
        protocolLog: protocolLog ?? this.protocolLog,
      );
}

/// Device Studio 控制器 (WORK_V3 §28/§29)：
/// 选择模拟设备 → 会话(连接/握手/同步) → UI 包解压 → UI Runtime → 日志收集。
class StudioController extends Notifier<StudioState> {
  StudioController({UiCache? cache}) : _cache = cache;

  /// 测试注入缓存目录 (生产用应用私有目录)。
  final UiCache? _cache;

  static const int _maxLogLines = 200;

  final List<String> _logLines = <String>[];

  StreamSubscription<DeviceState>? _stateSub;
  StreamSubscription<DeviceEvent>? _eventSub;

  // 资源引用私有缓存：onDispose 期间不能访问 state/ref
  DeviceClient? _client;
  UiServer? _uiServer;

  @override
  StudioState build() {
    ref.onDispose(_disposeResources);
    return const StudioState();
  }

  /// 启动模拟设备会话。
  Future<bool> start(ProtocolDevice device) async {
    await stop();
    final log = AppLog(level: LogLevel.trace, output: _appendLog);
    try {
      final client = DeviceClient(
        transport: device,
        deviceId: device.deviceId,
        log: log,
      );
      await client.connect();
      final ack = await client.hello();
      await client.syncState();
      client.startHeartbeat();

      // UI 包 (设备提供) → 解压缓存 → 静态根 (§15.3)
      String? staticRoot;
      final pkgBytes = device.resourceBytes('ui.pkg');
      if (pkgBytes != null) {
        final cache = _cache ?? await UiCache.open();
        staticRoot =
            await cache.store(device.deviceId, device.uiVersion, pkgBytes);
      }
      final uiServer = UiServer(client: client, staticRoot: staticRoot);
      await uiServer.start();

      _stateSub = client.states.listen((s) {
        state = state.copyWith(currentState: s);
      });
      _eventSub = client.events.listen((e) {
        _appendLog('EVENT ${e.event} ${e.data}');
      });

      _client = client;
      _uiServer = uiServer;
      state = StudioState(
        device: device,
        client: client,
        uiServer: uiServer,
        entryUrl: uiServer.entryUrl,
        currentState: client.currentState,
        helloAck: ack,
        protocolLog: List<String>.unmodifiable(_logLines),
      );
      return true;
    } catch (e) {
      _logLines.add('ERROR $e');
      state = StudioState(
        error: '$e',
        protocolLog: List<String>.unmodifiable(_logLines),
      );
      return false;
    }
  }

  /// 断开并释放会话。
  Future<void> stop() async {
    await _disposeResources();
    if (ref.mounted) {
      state = const StudioState(protocolLog: <String>[]);
    }
  }

  /// 资源释放 (provider dispose 与主动断开共用；不触碰 state/ref)。
  Future<void> _disposeResources() async {
    await _stateSub?.cancel();
    _stateSub = null;
    await _eventSub?.cancel();
    _eventSub = null;
    final client = _client;
    final uiServer = _uiServer;
    _client = null;
    _uiServer = null;
    if (client != null) {
      await uiServer?.stop();
      await client.dispose();
    }
  }

  /// 重置设备 (WORK_V3 §29)：断开 → 硬件/状态复位 → 重连 → 重新同步。
  Future<bool> reset() async {
    final client = state.client;
    final device = state.device;
    if (client == null || device == null) {
      return false;
    }
    try {
      client.stopHeartbeat();
      await device.disconnect();
      await device.reset();
      await device.connect(device.deviceId);
      await client.requestState();
      client.startHeartbeat();
      _appendLog('INFO 设备已重置');
      return true;
    } catch (e) {
      _appendLog('ERROR 重置失败: $e');
      return false;
    }
  }

  /// 发送命令 (Inspector 使用)。
  Future<DeviceResponse?> sendCommand(String cmd, Map<String, dynamic> params) async {
    final client = state.client;
    if (client == null) {
      return null;
    }
    try {
      return await client.command(cmd, params);
    } catch (e) {
      _appendLog('ERROR 命令失败: $e');
      return null;
    }
  }

  void _appendLog(String line) {
    _logLines.add(line);
    if (_logLines.length > _maxLogLines) {
      _logLines.removeRange(0, _logLines.length - _maxLogLines);
    }
    final current = state;
    if (current.isRunning) {
      state = current.copyWith(protocolLog: List<String>.unmodifiable(_logLines));
    }
  }
}

final studioControllerProvider =
    NotifierProvider<StudioController, StudioState>(StudioController.new);
