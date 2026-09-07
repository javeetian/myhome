import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../providers/device_session_provider.dart';
import '../../providers/ui_runtime_provider.dart';
import '../../ui_runtime/webview_host.dart';

/// 设备控制页：WebView 加载设备端 UI (由本地 UI Server 服务)。
class DevicePage extends ConsumerStatefulWidget {
  const DevicePage({super.key, required this.name});

  /// 设备展示名称。
  final String name;

  @override
  ConsumerState<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends ConsumerState<DevicePage> {
  Future<void> _disconnect() async {
    await ref.read(uiServerControllerProvider.notifier).stop();
    ref.read(deviceSessionControllerProvider.notifier).select(null);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: '断开并返回',
            onPressed: _disconnect,
          ),
        ],
      ),
      body: WebViewHost(url: AppConstants.proxyBaseUrl),
    );
  }
}
