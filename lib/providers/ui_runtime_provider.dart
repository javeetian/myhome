import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device/device_client.dart';
import '../ui_runtime/ui_server.dart';

/// UI Server 运行状态。
class UiServerState {
  const UiServerState({this.server, this.entryUrl, this.error});

  final UiServer? server;

  /// 页面入口 URL (含 session token 路径前缀)，供 WebView 加载。
  final String? entryUrl;

  final String? error;

  bool get isRunning => server != null;
}

/// UI Server 控制器 (WORK_V2 §12.3 uiRuntimeProvider 的 Phase 8 形态)。
class UiServerController extends Notifier<UiServerState> {
  @override
  UiServerState build() => const UiServerState();

  /// 以 [client] 启动本地 UI Server (127.0.0.1 随机端口 + session token)。
  /// [staticRoot] 为 UI 静态目录，Phase 9 起为 UI Package 缓存目录。
  Future<bool> start(DeviceClient client, {String? staticRoot}) async {
    await stop(); // 先停掉旧服务
    try {
      final server = UiServer(client: client, staticRoot: staticRoot);
      await server.start();
      state = UiServerState(server: server, entryUrl: server.entryUrl);
      return true;
    } catch (e) {
      state = UiServerState(error: '$e');
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
