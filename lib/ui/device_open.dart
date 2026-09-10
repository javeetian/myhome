import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ble/ble_transport.dart';
import '../device/connection_phase.dart';
import '../device/defined_virtual_device.dart';
import '../device/device_definition.dart';
import '../device/device_templates.dart';
import '../l10n/app_localizations.dart';
import '../providers/device_history_provider.dart';
import '../providers/device_session_provider.dart';
import '../providers/ui_runtime_provider.dart';
import '../ui_runtime/ui_package.dart';
import 'pages/device_page.dart';

/// 内置 Smart Light 演示设备 (WORK_V2 §30 硬件到位前的替代)：
/// App 侧走完整 DeviceClient → Protocol → Transport 链路，
/// UI 走完整 Phase 10 流程 (manifest → 下载 ui.pkg → 缓存)。
DefinedVirtualDevice buildDemoDevice() {
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
  return DefinedVirtualDevice(definition, uiPkgBytes: pkg);
}

/// 连接设备 → 启动 UI Server → 记入历史 → 跳转控制页。
///
/// 扫描页 (添加设备) 与主界面 (历史设备重连) 共用的完整流程：
/// 成功后当前路由被控制页替换，返回键直接回到主界面。
/// [transport] 缺省为真实 BLE 连接 ([bleTransportProvider])。
Future<void> openDeviceFlow(
  BuildContext context,
  WidgetRef ref, {
  required String deviceId,
  required String displayName,
  BleTransport? transport,
  DeviceHistoryKind historyKind = DeviceHistoryKind.ble,
}) async {
  final l10n = AppLocalizations.of(context)!;
  await ref
      .read(deviceSessionProvider.notifier)
      .connect(deviceId, transport: transport);
  final session = ref.read(deviceSessionProvider);
  if (session.phase == ConnectionPhase.error) {
    throw StateError(session.error ?? l10n.unknownError);
  }
  final client = ref.read(deviceClientProvider);
  if (client == null) {
    throw StateError(l10n.sessionNotEstablished);
  }
  final ok = await ref.read(uiServerControllerProvider.notifier).start(client);
  if (!ok) {
    final error = ref.read(uiServerControllerProvider).error;
    // 启动失败则断开本次会话，避免残留连接。
    await ref.read(deviceSessionProvider.notifier).disconnect();
    throw StateError(l10n.uiServerStartFailed(error ?? ''));
  }
  // UI 加载中 (Phase 9 §12.6)；WebView 页面加载完成后再置 connected
  ref.read(deviceSessionProvider.notifier).setPhase(ConnectionPhase.loadingUi);
  await ref
      .read(deviceHistoryProvider.notifier)
      .add(deviceId, displayName, historyKind);
  if (!context.mounted) {
    return;
  }
  await Navigator.of(context).pushReplacement<void, void>(
    MaterialPageRoute<void>(builder: (_) => DevicePage(name: displayName)),
  );
}
