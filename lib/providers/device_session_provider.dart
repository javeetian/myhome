import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device/device_session.dart';

/// 当前激活的设备会话 (BLE 或 Mock)。
class DeviceSessionController extends Notifier<DeviceSession?> {
  DeviceSession? _session;

  @override
  DeviceSession? build() {
    _session = null;
    ref.onDispose(() {
      _session?.dispose();
      _session = null;
    });
    return _session;
  }

  /// 切换会话：旧会话会被释放。
  void select(DeviceSession? session) {
    if (identical(_session, session)) {
      return;
    }
    _session?.dispose();
    _session = session;
    state = session;
  }
}

final deviceSessionControllerProvider =
    NotifierProvider<DeviceSessionController, DeviceSession?>(
  DeviceSessionController.new,
);
