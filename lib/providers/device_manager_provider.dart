import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device/device_session.dart';

/// 多设备会话记录 (WORK_V2 §22 数据层, Phase 12)。
///
/// UI 仍为单前台会话 ([deviceSessionProvider])；本 Manager 维护
/// 每个设备最近一次的会话快照，供多设备管理与调试面板使用。
/// 每设备独立 Transport / Session / State / UI Runtime 的
/// 完整多设备 UI 待云阶段实现 (§45 不过早优化)。
class DeviceManagerController extends Notifier<Map<String, DeviceSession>> {
  @override
  Map<String, DeviceSession> build() => const <String, DeviceSession>{};

  /// 记录/更新设备会话快照 (connect / disconnect / 断线时调用)。
  void upsert(DeviceSession session) {
    final deviceId = session.deviceId;
    if (deviceId == null) {
      return;
    }
    state = <String, DeviceSession>{...state, deviceId: session};
  }

  /// 移除设备会话记录。
  void remove(String deviceId) {
    if (!state.containsKey(deviceId)) {
      return;
    }
    final next = Map<String, DeviceSession>.of(state)..remove(deviceId);
    state = next;
  }

  /// 某设备最近一次会话快照。
  DeviceSession? of(String deviceId) => state[deviceId];
}

/// 多设备会话记录表 (§22)。
final deviceManagerProvider =
    NotifierProvider<DeviceManagerController, Map<String, DeviceSession>>(
  DeviceManagerController.new,
);
