import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ble/ble_peripheral.dart';
import '../ble/ble_transport.dart';
import '../device/connection_phase.dart';
import '../device/device_client.dart';
import '../device/device_session.dart';
import '../protocol/protocol_messages.dart';
import 'ble_provider.dart';
import 'device_manager_provider.dart';

/// 设备会话控制器 (WORK_V2 §12.4/§12.5 的单会话形态)。
///
/// 状态生命周期 (§12.6)：
///   disconnected → connecting → connected
///   connected → disconnecting → disconnected
///   任何状态 → error
///
/// 多设备 DeviceManager (会话 Map) 待多设备需求 (Phase 12/云阶段) 实现。
class DeviceSessionController extends Notifier<DeviceSession> {
  DeviceClient? _client;
  BleTransport? _transport;
  StreamSubscription<DeviceState>? _stateSub;
  StreamSubscription<BleConnectionState>? _connSub;
  bool _reconnecting = false;

  /// 心跳间隔 (Phase 12 §22 扩展；测试可缩短)。
  static Duration heartbeatInterval = const Duration(seconds: 10);

  /// 重连退避基数 (Phase 22；测试可缩短)。
  static Duration reconnectBaseDelay = const Duration(milliseconds: 500);

  /// 最大重连尝试次数 (Phase 22)。
  static int maxReconnectAttempts = 3;

  @override
  DeviceSession build() {
    ref.onDispose(() {
      _client?.dispose();
      _stateSub?.cancel();
      _connSub?.cancel();
    });
    return const DeviceSession.none();
  }

  /// 连接指定设备：创建 DeviceClient → 建立会话 → 订阅状态与断线。
  /// [transport] 可注入 (演示设备 / 测试)；缺省从 [bleTransportProvider] 读取。
  Future<void> connect(String deviceId, {BleTransport? transport}) async {
    await disconnect();
    final BleTransport resolved;
    if (transport != null) {
      resolved = transport;
    } else {
      resolved = ref.read(bleTransportProvider);
    }
    _transport = resolved;
    final client = DeviceClient(transport: resolved, deviceId: deviceId);
    _client = client;
    state = DeviceSession(
      phase: ConnectionPhase.connecting,
      deviceId: deviceId,
      client: client,
    );

    try {
      await client.connect();
      // HELLO 握手 (WORK_V2 §15.3/§39)：handshaking
      state = state.copyWith(phase: ConnectionPhase.handshaking);
      await client.hello();
      // 状态同步 (WORK_V2 §16.6)：设备是唯一数据源
      state = state.copyWith(phase: ConnectionPhase.syncingState);
      await client.syncState();
      _wireSession(client, resolved);
      // 心跳 (Phase 12 §22 扩展)：失联 → 断线流程 (§20)
      client.onConnectionLost = _onConnectionLost;
      client.startHeartbeat(interval: heartbeatInterval);
      state = state.copyWith(
        phase: ConnectionPhase.connected,
        deviceState: client.currentState,
        clearError: true,
      );
      ref.read(deviceManagerProvider.notifier).upsert(state);
    } catch (e) {
      _unwire();
      state = state.copyWith(phase: ConnectionPhase.error, error: '$e');
      ref.read(deviceManagerProvider.notifier).upsert(state);
      await client.dispose();
      _client = null;
    }
  }

  /// 断开当前会话 (§12.6 断线路径)。
  Future<void> disconnect() async {
    final client = _client;
    if (client == null) {
      return;
    }
    final deviceId = state.deviceId;
    state = state.copyWith(phase: ConnectionPhase.disconnecting);
    _unwire();
    _transport = null;
    await client.disconnect();
    _client = null;
    if (deviceId != null) {
      ref.read(deviceManagerProvider.notifier).upsert(DeviceSession(
            phase: ConnectionPhase.disconnected,
            deviceId: deviceId,
          ));
    }
    state = const DeviceSession.none();
  }

  /// 断线触发点 (设备侧断开 / 心跳失联) → 自动重连 (Phase 22, FRAMEWORK_V3 §36)。
  void _startReconnect() {
    if (_reconnecting || _transport == null) {
      return;
    }
    _reconnecting = true;
    _unwire();
    final deviceId = state.deviceId;
    if (deviceId == null) {
      _reconnecting = false;
      return;
    }
    state = state.copyWith(phase: ConnectionPhase.reconnecting);
    unawaited(_reconnectLoop(deviceId));
  }

  /// 重连循环：backoff 重试 → 成功恢复会话；耗尽 → disconnected。
  Future<void> _reconnectLoop(String deviceId) async {
    final transport = _transport;
    final oldClient = _client;
    try {
      for (var attempt = 1; attempt <= maxReconnectAttempts; attempt++) {
        await Future<void>.delayed(
            reconnectBaseDelay * (1 << (attempt - 1)));
        // 用户已主动断开 → 放弃重连
        if (state.phase != ConnectionPhase.reconnecting) {
          return;
        }
        final client = DeviceClient(transport: transport!, deviceId: deviceId);
        try {
          await client.connect();
          state = state.copyWith(phase: ConnectionPhase.handshaking);
          await client.hello();
          state = state.copyWith(phase: ConnectionPhase.syncingState);
          await client.syncState();
          // 重连成功：替换会话
          unawaited(oldClient?.dispose() ?? Future<void>.value());
          _client = client;
          client.onConnectionLost = _onConnectionLost;
          client.startHeartbeat(interval: heartbeatInterval);
          _wireSession(client, transport);
          state = state.copyWith(
            phase: ConnectionPhase.connected,
            deviceState: client.currentState,
            clearError: true,
          );
          ref.read(deviceManagerProvider.notifier).upsert(state);
          return;
        } catch (_) {
          await client.dispose();
          // 继续下一次尝试
        }
      }
      // 重连耗尽 → disconnected
      _client = null;
      final snapshot = DeviceSession(
        phase: ConnectionPhase.disconnected,
        deviceId: deviceId,
        deviceState: state.deviceState,
      );
      state = snapshot;
      ref.read(deviceManagerProvider.notifier).upsert(snapshot);
    } finally {
      _reconnecting = false;
    }
  }

  /// 心跳判定失联 (Phase 12) → 断线流程 (§20)。
  void _onConnectionLost() {
    final client = _client;
    final deviceId = state.deviceId;
    if (client == null || deviceId == null) {
      return;
    }
    _startReconnect();
  }

  /// 由外部阶段事件推进状态 (§12.6)：
  /// Phase 9 UI 加载 (loadingUi → connected) 等。
  /// error / disconnected / disconnecting 为终态或离线态，不可覆盖。
  void setPhase(ConnectionPhase phase) {
    final current = state.phase;
    if (current == ConnectionPhase.error ||
        current == ConnectionPhase.disconnected ||
        current == ConnectionPhase.disconnecting) {
      return;
    }
    state = state.copyWith(phase: phase);
  }

  void _wireSession(DeviceClient client, BleTransport transport) {
    _stateSub = client.states.listen((deviceState) {
      state = state.copyWith(deviceState: deviceState);
    });
    // 设备侧主动断线 → 自动重连 (Phase 22, §20/§36)
    _connSub = transport.connectionStates.listen((connectionState) {
      if (connectionState == BleConnectionState.disconnected &&
          state.phase == ConnectionPhase.connected) {
        _startReconnect();
      }
    });
  }

  void _unwire() {
    _stateSub?.cancel();
    _stateSub = null;
    _connSub?.cancel();
    _connSub = null;
  }
}

/// 当前设备会话 (§12.3 deviceSessionProvider)。
final deviceSessionProvider =
    NotifierProvider<DeviceSessionController, DeviceSession>(
  DeviceSessionController.new,
);

/// 当前会话的 DeviceClient (§12.3 deviceClientProvider，UI Runtime 使用)。
final deviceClientProvider = Provider<DeviceClient?>(
  (ref) => ref.watch(deviceSessionProvider).client,
);

/// 当前连接状态 (§12.3)。
final connectionPhaseProvider = Provider<ConnectionPhase>(
  (ref) => ref.watch(deviceSessionProvider).phase,
);

/// 当前设备状态 (§12.3 deviceStateProvider)。
final deviceStateProvider = Provider<DeviceState?>(
  (ref) => ref.watch(deviceSessionProvider).deviceState,
);

/// 设备 Manifest (§12.3 deviceManifestProvider，Phase 10 实现)。
/// UI Cache (§12.3 uiCacheProvider) 与 UI Runtime (§12.3 uiRuntimeProvider)
/// 分别在 Phase 10 / Phase 9 接入。
