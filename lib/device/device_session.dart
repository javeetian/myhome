import 'connection_phase.dart';
import 'device_client.dart';
import '../protocol/protocol_messages.dart';

/// 设备会话快照 (WORK_V2 §12.5)：Riverpod 不可变状态。
///
/// ```text
/// DeviceSession (§12.5)
/// ├── Connection State  → phase
/// ├── Device State      → deviceState (Phase 11 完整语义)
/// ├── DeviceClient      → client (UI Runtime 经此访问设备)
/// └── UI Runtime        → Phase 9 接入
/// ```
class DeviceSession {
  const DeviceSession({
    required this.phase,
    this.deviceId,
    this.client,
    this.deviceState,
    this.error,
  });

  /// 初始 (未连接) 快照。
  const DeviceSession.none() : this(phase: ConnectionPhase.disconnected);

  final ConnectionPhase phase;
  final String? deviceId;
  final DeviceClient? client;

  /// 最近一次设备状态 (Phase 11 引入 Patch 应用与版本 Gap 检测)。
  final DeviceState? deviceState;

  /// 最近一次错误信息 (phase == error 时有效)。
  final String? error;

  DeviceSession copyWith({
    ConnectionPhase? phase,
    String? deviceId,
    DeviceClient? client,
    DeviceState? deviceState,
    String? error,
    bool clearError = false,
  }) {
    return DeviceSession(
      phase: phase ?? this.phase,
      deviceId: deviceId ?? this.deviceId,
      client: client ?? this.client,
      deviceState: deviceState ?? this.deviceState,
      error: clearError ? null : (error ?? this.error),
    );
  }
}
