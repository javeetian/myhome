import 'webview_env_stub.dart'
    if (dart.library.io) 'webview_env_io.dart';

/// 初始化 WebView 运行环境 (WORK_V3 Phase 0)。
/// Windows：webview_windows 环境初始化 (Edge WebView2)；
/// 其他平台：no-op。
Future<void> initializeWebViewEnvironment() =>
    initializeWebViewEnvironmentImpl();
