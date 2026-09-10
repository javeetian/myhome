import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../device/connection_phase.dart';
import '../../l10n/app_localizations.dart';
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
  bool _wasReconnecting = false;

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

  /// 重连成功后重启 UI Server (新 client) 并重载 WebView (Phase 22)。
  Future<void> _restartUiServer() async {
    final client = ref.read(deviceClientProvider);
    if (client == null) {
      return;
    }
    // 内部走 UiRuntime：UI 缓存命中，秒级恢复
    await ref.read(uiServerControllerProvider.notifier).start(client);
  }

  /// 设备断开/异常/重连 → 状态机处理 (§20, Phase 22)。
  void _onPhaseChanged(ConnectionPhase phase) {
    final l10n = AppLocalizations.of(context)!;
    if (_leaving) {
      return;
    }
    if (phase == ConnectionPhase.reconnecting) {
      _wasReconnecting = true;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.reconnecting)));
      return;
    }
    if (phase == ConnectionPhase.connected && _wasReconnecting) {
      _wasReconnecting = false;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.reconnected)));
      unawaited(_restartUiServer());
      return;
    }
    if (phase != ConnectionPhase.disconnected &&
        phase != ConnectionPhase.error) {
      return;
    }
    _leaving = true;
    final message = phase == ConnectionPhase.error
        ? l10n.deviceError(ref.read(deviceSessionProvider).error ?? '')
        : l10n.deviceDisconnected;
    ref.read(uiServerControllerProvider.notifier).stop();
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
            tooltip: l10n.developerMode,
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              builder: (_) => const DeveloperPanel(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: l10n.disconnectAndBack,
            onPressed: _disconnect,
          ),
        ],
      ),
      body: entryUrl == null
          ? Center(child: Text(l10n.uiServerNotStarted))
          : WebViewHost(
              key: ValueKey<String>(entryUrl), // 重连后 entryUrl 变化 → 重建重载
              url: entryUrl,
              onPageLoaded: _onUiLoaded,
            ),
    );
  }
}
