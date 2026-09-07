import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ble/ble_peripheral.dart';
import '../ble/ble_transport.dart';
import '../device/connection_phase.dart';
import '../device/device_client.dart';
import '../device/device_session.dart';
import '../protocol/protocol_messages.dart';
import 'ble_provider.dart';

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
  StreamSubscription<DeviceState>? _stateSub;
  StreamSubscription<BleConnectionState>? _connSub;

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
  Future<void> connect(String deviceId) async {
    await disconnect();
    final transport = ref.read(bleTransportProvider);
    final client = DeviceClient(transport: transport, deviceId: deviceId);
    _client = client;
    state = DeviceSession(
      phase: ConnectionPhase.connecting,
      deviceId: deviceId,
      client: client,
    );

    try {
      await client.connect();
      _wireSession(client, transport);
      state = state.copyWith(phase: ConnectionPhase.connected, clearError: true);
    } catch (e) {
      _unwire();
      state = state.copyWith(phase: ConnectionPhase.error, error: '$e');
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
    state = state.copyWith(phase: ConnectionPhase.disconnecting);
    _unwire();
    await client.disconnect();
    _client = null;
    state = const DeviceSession.none();
  }

  void _wireSession(DeviceClient client, BleTransport transport) {
    _stateSub = client.states.listen((deviceState) {
      state = state.copyWith(deviceState: deviceState);
    });
    // 设备侧主动断线 → 会话回到 disconnected (§20)
    _connSub = transport.connectionStates.listen((connectionState) {
      if (connectionState == BleConnectionState.disconnected &&
          state.phase == ConnectionPhase.connected) {
        state = DeviceSession(
          phase: ConnectionPhase.disconnected,
          deviceId: state.deviceId,
          client: state.client,
          deviceState: state.deviceState,
        );
        _client = null;
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
