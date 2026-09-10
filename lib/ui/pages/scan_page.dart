import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/ble_provider.dart';
import '../../providers/device_history_provider.dart';
import '../device_open.dart';

/// 添加设备页：扫描真实 BLE 设备，或使用演示设备跑通完整链路 (无需硬件)。
/// 连接成功后记入历史并跳转控制页 (返回键回主界面)。
class ScanPage extends ConsumerStatefulWidget {
  const ScanPage({super.key});

  @override
  ConsumerState<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends ConsumerState<ScanPage> {
  bool _busy = false;

  /// 请求 Android 蓝牙权限后开始扫描。
  Future<void> _startScan() async {
    final l10n = AppLocalizations.of(context)!;
    final statuses = await <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();
    if (!statuses.values.every((s) => s.isGranted)) {
      _showSnack(l10n.scanPermissionDenied);
      return;
    }
    try {
      await ref.read(bleScannerProvider).startScan();
    } catch (e) {
      _showSnack(l10n.scanFailed(e.toString()));
    }
  }

  /// 真实设备：连接 → 启动 UI Server → 记入历史 → 跳转控制页。
  Future<void> _openDevice(DiscoveredDevice device) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _busy = true);
    try {
      await openDeviceFlow(
        context,
        ref,
        deviceId: device.id,
        // 广播名缺失时用 id 兜底，避免把本地化文案存进历史
        displayName: device.name.isNotEmpty ? device.name : device.id,
      );
    } catch (e) {
      _showSnack(l10n.connectFailed(e.toString()));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  /// 演示设备 (WORK_V2 §30)：与真实设备走完全相同的流程。
  Future<void> _openDemo() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _busy = true);
    final demo = buildDemoDevice();
    try {
      await openDeviceFlow(
        context,
        ref,
        deviceId: demo.deviceId,
        displayName: demo.name,
        transport: demo,
        historyKind: DeviceHistoryKind.demo,
      );
    } catch (e) {
      _showSnack(l10n.demoFailed(e.toString()));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final results =
        ref.watch(scanResultsProvider).value ?? const <DiscoveredDevice>[];
    final bleStatus = ref.watch(bleStatusProvider).value;
    final isScanning = ref.watch(isScanningProvider).value ?? false;

    // 按 id 去重
    final seen = <String>{};
    final devices = results.where((d) => seen.add(d.id)).toList();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.addDevice)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: isScanning
            ? () => ref.read(bleScannerProvider).stopScan()
            : _startScan,
        icon: Icon(isScanning ? Icons.stop : Icons.bluetooth_searching),
        label: Text(isScanning ? l10n.stopScan : l10n.startScan),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (bleStatus != null && bleStatus != BleStatus.ready)
            Card(
              child: ListTile(
                leading: const Icon(Icons.warning_amber),
                title: Text(_statusText(l10n, bleStatus)),
              ),
            ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.science),
              title: Text(l10n.demoCardTitle),
              subtitle: Text(l10n.demoCardSubtitle),
              onTap: _busy ? null : _openDemo,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              l10n.scanResultCount(devices.length),
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          if (devices.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(child: Text(l10n.scanEmpty)),
            ),
          ...devices.map(
            (d) => Card(
              child: ListTile(
                leading: const Icon(Icons.devices),
                title: Text(d.name.isNotEmpty ? d.name : l10n.unknownDevice),
                subtitle: Text('${d.id}  RSSI: ${d.rssi}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _busy ? null : () => _openDevice(d),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 蓝牙状态 → 用户提示文案。
  String _statusText(AppLocalizations l10n, BleStatus status) {
    switch (status) {
      case BleStatus.poweredOff:
        return l10n.blePoweredOff;
      case BleStatus.unauthorized:
        return l10n.bleUnauthorized;
      case BleStatus.locationServicesDisabled:
        return l10n.bleLocationDisabled;
      case BleStatus.unsupported:
      case BleStatus.unknown:
        return l10n.bleUnsupported;
      case BleStatus.ready:
        return '';
    }
  }
}
