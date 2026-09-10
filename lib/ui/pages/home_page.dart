import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/device_history_provider.dart';
import '../device_open.dart';
import 'scan_page.dart';
import 'settings_page.dart';

/// 主界面：历史设备卡片列表 (米家式布局)。
///
/// - 左上角设置 → [SettingsPage]
/// - 右上角添加 → [ScanPage]
/// - 中间卡片列表：之前连接过的设备；无设备时中央显示大添加按钮
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  bool _busy = false;

  /// 重连历史设备：真实 BLE 或演示设备 → 控制页。
  Future<void> _openDevice(DeviceHistoryEntry entry) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _busy = true);
    try {
      if (entry.kind == DeviceHistoryKind.demo) {
        final demo = buildDemoDevice();
        await openDeviceFlow(
          context,
          ref,
          deviceId: demo.deviceId,
          displayName: demo.name,
          transport: demo,
          historyKind: DeviceHistoryKind.demo,
        );
      } else {
        await openDeviceFlow(
          context,
          ref,
          deviceId: entry.id,
          displayName: entry.name,
        );
      }
    } catch (e) {
      _showSnack(l10n.connectFailed(e.toString()));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _openAdd() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ScanPage()),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
    );
  }

  /// 移除历史条目前确认。
  Future<void> _confirmRemove(DeviceHistoryEntry entry) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Text(l10n.removeDeviceConfirm(entry.name)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.removeDevice),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(deviceHistoryProvider.notifier).remove(entry.id);
    }
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// 卡片副标题：最近连接时间 (按当前语言格式化)。
  String _lastConnectedText(AppLocalizations l10n, DateTime time) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final formatted = DateFormat.yMMMd(locale).add_Hm().format(time);
    return l10n.lastConnected(formatted);
  }

  /// 空状态：中央大添加按钮。
  Widget _buildEmpty(AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          FilledButton(
            style: FilledButton.styleFrom(
              shape: const CircleBorder(),
              padding: const EdgeInsets.all(32),
            ),
            onPressed: _busy ? null : _openAdd,
            child: const Icon(Icons.add, size: 48),
          ),
          const SizedBox(height: 16),
          Text(l10n.homeEmptyHint),
        ],
      ),
    );
  }

  Widget _buildDeviceCard(AppLocalizations l10n, DeviceHistoryEntry entry) {
    final isDemo = entry.kind == DeviceHistoryKind.demo;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(isDemo ? Icons.lightbulb : Icons.devices),
        ),
        title: Text(entry.name),
        subtitle: Text(_lastConnectedText(l10n, entry.addedAt)),
        trailing: PopupMenuButton<String>(
          tooltip: l10n.removeDevice,
          onSelected: (value) {
            if (value == 'remove') {
              _confirmRemove(entry);
            }
          },
          itemBuilder: (_) => <PopupMenuEntry<String>>[
            PopupMenuItem<String>(
              value: 'remove',
              child: Text(l10n.removeDevice),
            ),
          ],
        ),
        onTap: _busy ? null : () => _openDevice(entry),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final history = ref.watch(deviceHistoryProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.settings),
          tooltip: l10n.settings,
          onPressed: _openSettings,
        ),
        title: const Text('MyHome'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: l10n.addDevice,
            onPressed: _busy ? null : _openAdd,
          ),
        ],
      ),
      body: history.isEmpty
          ? _buildEmpty(l10n)
          : ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                for (final entry in history) _buildDeviceCard(l10n, entry),
              ],
            ),
    );
  }
}
