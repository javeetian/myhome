import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';

/// Windows WebView 实现 (webview_windows / Edge WebView2, WORK_V3 §28)。
class WindowsWebViewHost extends StatefulWidget {
  const WindowsWebViewHost({super.key, required this.url, this.onPageLoaded});

  /// 设备 UI 入口地址 (由本地 UI Server 服务)。
  final String url;

  /// 页面加载完成回调 (UI Ready)。
  final VoidCallback? onPageLoaded;

  @override
  State<WindowsWebViewHost> createState() => _WindowsWebViewHostState();
}

class _WindowsWebViewHostState extends State<WindowsWebViewHost> {
  final WebviewController _controller = WebviewController();

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    await _controller.initialize();
    _controller.loadingState.listen((state) {
      if (state == LoadingState.navigationCompleted) {
        widget.onPageLoaded?.call();
      }
    });
    await _controller.loadUrl(widget.url);
    if (mounted) {
      setState(() {}); // 初始化完成后重建以挂载 Webview
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _controller.value.isInitialized
        ? Webview(_controller)
        : const Center(child: CircularProgressIndicator());
  }
}
