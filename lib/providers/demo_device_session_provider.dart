import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device/demo_device_channel.dart';

/// 当前激活的设备会话 (BLE 或 Mock)。
class DemoDeviceSessionController extends Notifier<DemoDeviceChannel?> {
  DemoDeviceChannel? _session;

  @override
  DemoDeviceChannel? build() {
    _session = null;
    ref.onDispose(() {
      _session?.dispose();
      _session = null;
    });
    return _session;
  }

  /// 切换会话：旧会话会被释放。
  void select(DemoDeviceChannel? session) {
    if (identical(_session, session)) {
      return;
    }
    _session?.dispose();
    _session = session;
    state = session;
  }
}

final demoDeviceSessionControllerProvider =
    NotifierProvider<DemoDeviceSessionController, DemoDeviceChannel?>(
  DemoDeviceSessionController.new,
);
