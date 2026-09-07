import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../device/device_session.dart';
import '../ui_runtime/ui_server.dart';

/// UI Server 运行状态。
class UiServerState {
  const UiServerState({this.server, this.error});

  final UiServer? server;
  final String? error;

  bool get isRunning => server != null;
}

/// UI Server 控制器：负责启动/停止 App 内置本地服务器。
class UiServerController extends Notifier<UiServerState> {
  @override
  UiServerState build() => const UiServerState();

  /// 以 [session] 为设备通道启动 UI Server，返回是否成功。
  Future<bool> start(DeviceSession session) async {
    await stop(); // 先停掉旧服务
    try {
      final server = UiServer(session);
      await server.start(port: AppConstants.proxyPort);
      state = UiServerState(server: server);
      return true;
    } catch (e) {
      state = UiServerState(error: e.toString());
      return false;
    }
  }

  Future<void> stop() async {
    final server = state.server;
    if (server != null) {
      await server.stop();
    }
    state = const UiServerState();
  }
}

final uiServerControllerProvider =
    NotifierProvider<UiServerController, UiServerState>(
  UiServerController.new,
);
