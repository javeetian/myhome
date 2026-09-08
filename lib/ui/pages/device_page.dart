import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../device/connection_phase.dart';
import '../../providers/device_session_provider.dart';
import '../../providers/ui_runtime_provider.dart';
import '../../ui_runtime/webview_host.dart';
import 'developer_panel.dart';

/// 设备控制页：WebView 加载设备端 UI (由本地 UI Server 服务)。
///
/// 生命周期 (WORK_V2 §23)：
///   UI 加载完成 → phase = connected；
///   设备断开/异常 → 提示并自动返回扫描页 (§20)。
class DevicePage extends ConsumerStatefulWidget {
  const DevicePage({super.key, required this.name});

  /// 设备展示名称。
  final String name;

  @override
  ConsumerState<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends ConsumerState<DevicePage> {
  bool _leaving = false;

  Future<void> _disconnect() async {
    _leaving = true;
    await ref.read(uiServerControllerProvider.notifier).stop();
    await ref.read(deviceSessionProvider.notifier).disconnect();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  /// WebView 页面加载完成 → UI Ready (§23)。
  void _onUiLoaded() {
    ref.read(deviceSessionProvider.notifier).setPhase(ConnectionPhase.connected);
  }

  /// 设备断开/异常 → 提示并自动返回 (§20)。
  void _onPhaseChanged(ConnectionPhase phase) {
    if (_leaving) {
      return;
    }
    if (phase != ConnectionPhase.disconnected &&
        phase != ConnectionPhase.error) {
      return;
    }
    _leaving = true;
    final message = phase == ConnectionPhase.error
        ? '设备异常: ${ref.read(deviceSessionProvider).error}'
        : '设备已断开';
    ref.read(uiServerControllerProvider.notifier).stop();
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(connectionPhaseProvider, (previous, next) {
      _onPhaseChanged(next);
    });
    final entryUrl = ref.watch(uiServerControllerProvider).entryUrl;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.bug_report),
            tooltip: '开发者模式',
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              builder: (_) => const DeveloperPanel(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: '断开并返回',
            onPressed: _disconnect,
          ),
        ],
      ),
      body: entryUrl == null
          ? const Center(child: Text('UI 服务未启动'))
          : WebViewHost(url: entryUrl, onPageLoaded: _onUiLoaded),
    );
  }
}
