import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../device/connection_phase.dart';
import '../../device/defined_virtual_device.dart';
import '../../device/device_definition.dart';
import '../../providers/ble_provider.dart';
import '../../providers/device_session_provider.dart';
import '../../providers/ui_runtime_provider.dart';
import '../../device/device_templates.dart';
import '../../ui_runtime/ui_package.dart';
import 'device_page.dart';

/// 设备扫描页：扫描真实 BLE 设备，或使用演示设备跑通完整链路 (无需硬件)。
class ScanPage extends ConsumerStatefulWidget {
  const ScanPage({super.key});

  @override
  ConsumerState<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends ConsumerState<ScanPage> {
  bool _busy = false;

  /// 请求 Android 蓝牙权限后开始扫描。
  Future<void> _startScan() async {
    final statuses = await <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();
    if (!statuses.values.every((s) => s.isGranted)) {
      _showSnack('缺少蓝牙权限，请在系统设置中授权');
      return;
    }
    try {
      await ref.read(bleScannerProvider).startScan();
    } catch (e) {
      _showSnack('扫描失败: $e');
    }
  }

  /// 真实设备：连接 → 启动 UI Server → 跳转控制页。
  Future<void> _openDevice(DiscoveredDevice device) async {
    setState(() => _busy = true);
    try {
      await ref.read(deviceSessionProvider.notifier).connect(device.id);
      await _startUiServer(device.name.isNotEmpty ? device.name : device.id);
    } catch (e) {
      _showSnack('连接失败: $e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  /// 演示设备 (WORK_V2 §30 硬件到位前的替代)：内置 Smart Light 定义驱动的
  /// 通用模拟器，App 侧走完整 DeviceClient → Protocol → Transport 链路，
  /// UI 走完整 Phase 10 流程 (manifest → 下载 ui.pkg → 缓存)。
  Future<void> _openDemo() async {
    setState(() => _busy = true);
    final definition = DeviceDefinition.fromYaml(
      DeviceTemplates.deviceYaml('smart_light', 'Smart Light', 'L100'),
    );
    final pkg = UiPackage.pack(<String, Uint8List>{
      'manifest.json': Uint8List.fromList(
        utf8.encode(DeviceTemplates.uiManifest('smart_light', 'L100')),
      ),
      'index.html': Uint8List.fromList(
        utf8.encode(DeviceTemplates.uiIndexHtml('Smart Light')),
      ),
    });
    final demo = DefinedVirtualDevice(definition, uiPkgBytes: pkg);
    try {
      await ref
          .read(deviceSessionProvider.notifier)
          .connect(demo.deviceId, transport: demo);
      await _startUiServer(demo.name);
    } catch (e) {
      _showSnack('演示启动失败: $e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  /// 启动 UI Server 并跳转设备控制页。
  /// UI 静态目录由 UiRuntime 解析 (Phase 10：manifest → 缓存 → 下载)。
  Future<void> _startUiServer(String name) async {
    final client = ref.read(deviceClientProvider);
    if (client == null) {
      throw StateError('设备会话未建立');
    }
    final ok = await ref.read(uiServerControllerProvider.notifier).start(client);
    if (!ok) {
      final error = ref.read(uiServerControllerProvider).error;
      throw StateError('UI Server 启动失败: $error');
    }
    // UI 加载中 (Phase 9 §12.6)；WebView 页面加载完成后再置 connected
    ref.read(deviceSessionProvider.notifier).setPhase(ConnectionPhase.loadingUi);
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => DevicePage(name: name)),
    );
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
    final results =
        ref.watch(scanResultsProvider).value ?? const <DiscoveredDevice>[];
    final bleStatus = ref.watch(bleStatusProvider).value;
    final isScanning = ref.watch(isScanningProvider).value ?? false;

    // 按 id 去重
    final seen = <String>{};
    final devices = results.where((d) => seen.add(d.id)).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('设备扫描')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: isScanning
            ? () => ref.read(bleScannerProvider).stopScan()
            : _startScan,
        icon: Icon(isScanning ? Icons.stop : Icons.bluetooth_searching),
        label: Text(isScanning ? '停止扫描' : '开始扫描'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (bleStatus != null && bleStatus != BleStatus.ready)
            Card(
              child: ListTile(
                leading: const Icon(Icons.warning_amber),
                title: Text(_statusText(bleStatus)),
              ),
            ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.science),
              title: const Text('Mock 设备演示'),
              subtitle: const Text('无需真实硬件，模拟完整交互链路'),
              onTap: _busy ? null : _openDemo,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '扫描结果 (${devices.length})',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          if (devices.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('暂未发现设备，点击右下角开始扫描')),
            ),
          ...devices.map(
            (d) => Card(
              child: ListTile(
                leading: const Icon(Icons.devices),
                title: Text(_displayName(d)),
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
  String _statusText(BleStatus status) {
    switch (status) {
      case BleStatus.poweredOff:
        return '蓝牙未开启';
      case BleStatus.unauthorized:
        return '蓝牙权限未授权，请在系统设置中开启';
      case BleStatus.locationServicesDisabled:
        return '定位服务未开启';
      case BleStatus.unsupported:
      case BleStatus.unknown:
        return '当前平台不支持 BLE';
      case BleStatus.ready:
        return '';
    }
  }

  /// 设备名 (广播名)，无名字时显示 id。
  String _displayName(DiscoveredDevice d) {
    return d.name.isNotEmpty ? d.name : '未知设备';
  }
}
