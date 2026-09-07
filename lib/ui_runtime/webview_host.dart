import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// WebView 宿主：负责创建 WebView 并加载设备 UI。
/// 对应 FRAMEWORK_V2 §29 UI Runtime 的 WebView 部分。
class WebViewHost extends StatefulWidget {
  const WebViewHost({super.key, required this.url});

  /// 设备 UI 入口地址 (由本地 UI Server 服务)。
  final String url;

  @override
  State<WebViewHost> createState() => _WebViewHostState();
}

class _WebViewHostState extends State<WebViewHost> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}
