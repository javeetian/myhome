import 'package:flutter/material.dart';

import 'webview_host_stub.dart'
    if (dart.library.io) 'webview_host_io.dart' show buildHost;

/// WebView 宿主 (WORK_V3 桌面版扩展)：
/// Windows → webview_windows (Edge WebView2)；
/// Android/iOS/macOS → webview_flutter；web → 占位。
/// 对应 WORK_V2 §29 UI Runtime 的 WebView 部分。
class WebViewHost extends StatelessWidget {
  const WebViewHost({super.key, required this.url, this.onPageLoaded});

  /// 设备 UI 入口地址 (由本地 UI Server 服务)。
  final String url;

  /// 页面加载完成回调 (UI Ready, WORK_V2 §23)。
  final VoidCallback? onPageLoaded;

  @override
  Widget build(BuildContext context) {
    return buildHost(url: url, onPageLoaded: onPageLoaded);
  }
}
