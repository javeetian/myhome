import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Android / iOS / macOS WebView 实现 (webview_flutter)。
class MobileWebViewHost extends StatefulWidget {
  const MobileWebViewHost({super.key, required this.url, this.onPageLoaded});

  /// 设备 UI 入口地址 (由本地 UI Server 服务)。
  final String url;

  /// 页面加载完成回调 (UI Ready, WORK_V2 §23)。
  final VoidCallback? onPageLoaded;

  @override
  State<MobileWebViewHost> createState() => _MobileWebViewHostState();
}

class _MobileWebViewHostState extends State<MobileWebViewHost> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => widget.onPageLoaded?.call(),
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}
