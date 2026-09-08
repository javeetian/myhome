import 'dart:io';

import 'package:webview_windows/webview_windows.dart';

/// io 平台：Windows 初始化 WebView2 环境 (全局一次)。
Future<void> initializeWebViewEnvironmentImpl() async {
  if (Platform.isWindows) {
    await WebviewController.initializeEnvironment();
  }
}
