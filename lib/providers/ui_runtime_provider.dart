import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device/device_client.dart';
import '../device/device_manifest.dart';
import '../ui_runtime/ui_cache.dart';
import '../ui_runtime/ui_runtime.dart';
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

/// UI Server 控制器 (WORK_V2 §12.3 uiRuntimeProvider)。
class UiServerController extends Notifier<UiServerState> {
  @override
  UiServerState build() => const UiServerState();

  /// 以 [client] 启动本地 UI Server (127.0.0.1 随机端口 + session token)。
  /// 未提供 [staticRoot] 时走 Phase 10 UI Runtime 流程：
  /// manifest → 缓存命中检查 → 下载 ui.pkg → 校验 → 解包 (§15.3)。
  Future<bool> start(DeviceClient client, {String? staticRoot}) async {
    await stop(); // 先停掉旧服务
    try {
      String? root = staticRoot;
      DeviceManifest? manifest;
      if (root == null) {
        final cache = await UiCache.open();
        final result = await UiRuntime(client: client, cache: cache).loadUi();
        root = result.rootDir;
        manifest = result.manifest;
      }
      final server = UiServer(client: client, staticRoot: root, manifest: manifest);
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
