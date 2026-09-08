import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device/demo_device.dart';
import '../device/virtual_light.dart';
import '../ui_runtime/webview_host.dart';
import 'studio_controller.dart';

/// Device Studio 主页面 (WORK_V3 §22/§30)：
/// 三栏布局 —— 设备列表 | UI 预览 + Protocol Console | Inspector。
class StudioHomePage extends ConsumerWidget {
  const StudioHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Studio'),
        actions: <Widget>[
          if (ref.watch(studioControllerProvider).isRunning)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '重置设备',
              onPressed: () =>
                  ref.read(studioControllerProvider.notifier).reset(),
            ),
          if (ref.watch(studioControllerProvider).isRunning)
            IconButton(
              icon: const Icon(Icons.stop),
              tooltip: '断开',
              onPressed: () => ref.read(studioControllerProvider.notifier).stop(),
            ),
        ],
      ),
      body: const Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _DeviceListPanel(),
          VerticalDivider(width: 1),
          Expanded(child: _CenterPanel()),
          VerticalDivider(width: 1),
          _InspectorPanel(),
        ],
      ),
    );
  }
}

/// 左栏：设备列表 (WORK_V3 §29 Load UI Package / Select Device)。
class _DeviceListPanel extends ConsumerWidget {
  const _DeviceListPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studio = ref.watch(studioControllerProvider);
    final currentDeviceId = studio.device?.deviceId;

    return SizedBox(
      width: 220,
      child: ListView(
        padding: const EdgeInsets.all(8),
        children: <Widget>[
          Text('设备', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          _deviceCard(
            context,
            ref,
            title: 'Smart Light (L100)',
            subtitle: 'VirtualLight · power/brightness/色温',
            deviceId: VirtualLight().deviceId,
            isRunning: currentDeviceId == VirtualLight().deviceId && studio.isRunning,
            onStart: () async {
              // 尝试加载构建产物 ui.pkg (若存在)
              final pkgFile = File('devices/smart_light/build/ui.pkg');
              final pkg = pkgFile.existsSync()
                  ? pkgFile.readAsBytesSync()
                  : null;
              await ref
                  .read(studioControllerProvider.notifier)
                  .start(VirtualLight(uiPkgBytes: pkg));
            },
          ),
          _deviceCard(
            context,
            ref,
            title: 'Demo Light',
            subtitle: '内置 UI 演示设备',
            deviceId: DemoDevice().deviceId,
            isRunning:
                currentDeviceId == DemoDevice().deviceId && studio.isRunning,
            onStart: () => ref
                .read(studioControllerProvider.notifier)
                .start(DemoDevice()),
          ),
        ],
      ),
    );
  }

  Widget _deviceCard(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required String subtitle,
    required String deviceId,
    required bool isRunning,
    required Future<void> Function() onStart,
  }) {
    return Card(
      child: ListTile(
        leading: Icon(isRunning ? Icons.lightbulb : Icons.lightbulb_outline),
        title: Text(title),
        subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: isRunning
            ? const Icon(Icons.check_circle, color: Colors.green)
            : const Icon(Icons.play_arrow),
        onTap: isRunning ? null : onStart,
      ),
    );
  }
}

/// 中栏：UI 预览 + Protocol Console (WORK_V3 §24/§30)。
class _CenterPanel extends ConsumerWidget {
  const _CenterPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studio = ref.watch(studioControllerProvider);
    return Column(
      children: <Widget>[
        Expanded(
          child: studio.entryUrl != null
              ? WebViewHost(url: studio.entryUrl!)
              : Center(
                  child: Text(
                    studio.error != null
                        ? '启动失败: ${studio.error}'
                        : '选择左侧设备开始模拟',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
        ),
        const Divider(height: 1),
        _ProtocolConsole(lines: studio.protocolLog),
      ],
    );
  }
}

/// Protocol Console (WORK_V3 §24)：TX/RX 帧级日志。
class _ProtocolConsole extends StatelessWidget {
  const _ProtocolConsole({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 160,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              'Protocol Console',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: lines.length,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                child: Text(
                  lines[index],
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 右栏：Inspector (WORK_V3 §23/§31)。
class _InspectorPanel extends ConsumerWidget {
  const _InspectorPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studio = ref.watch(studioControllerProvider);
    final ack = studio.helloAck;
    final state = studio.currentState;
    final stats = studio.client?.stats;

    return SizedBox(
      width: 260,
      child: ListView(
        padding: const EdgeInsets.all(8),
        children: <Widget>[
          Text('Inspector', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          _row(context, 'Device ID', studio.device?.deviceId ?? '-'),
          _row(context, 'Model', ack?.deviceModel ?? '-'),
          _row(context, 'Protocol', '${ack?.protocolVersion ?? 1}'),
          _row(context, 'API Version', '1'),
          _row(context, 'UI Version', ack?.uiVersion ?? '-'),
          _row(context, 'State Version', '${state?.version ?? '-'}'),
          _row(context, 'Connection', studio.isRunning ? 'connected' : '-'),
          _row(context, 'TX Bytes', '${stats?.txBytes ?? 0}'),
          _row(context, 'RX Bytes', '${stats?.rxBytes ?? 0}'),
          _row(context, 'Retry Count', '${stats?.retries ?? 0}'),
          if (studio.error != null)
            _row(context, 'Last Error', studio.error!),
          const Divider(),
          Text('State', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              state == null
                  ? '-'
                  : const JsonEncoder.withIndent('  ').convert(state.state),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
          const Divider(),
          Text('Command', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          ..._commandButtons(context, ref),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      );

  List<Widget> _commandButtons(BuildContext context, WidgetRef ref) {
    final studio = ref.watch(studioControllerProvider);
    final device = studio.device;
    final notifier = ref.read(studioControllerProvider.notifier);
    if (device is VirtualLight) {
      final power = studio.currentState?.state['power'] == true;
      return <Widget>[
        FilledButton(
          onPressed: studio.isRunning
              ? () => notifier.sendCommand(
                  'light.set_power', <String, dynamic>{'power': !power})
              : null,
          child: Text(power ? '关灯' : '开灯'),
        ),
        const SizedBox(height: 6),
        FilledButton.tonal(
          onPressed: studio.isRunning
              ? () => notifier.sendCommand(
                  'light.set_brightness', <String, dynamic>{'value': 50})
              : null,
          child: const Text('亮度 50%'),
        ),
        const SizedBox(height: 6),
        FilledButton.tonal(
          onPressed: studio.isRunning
              ? () => notifier.sendCommand('light.set_color_temperature',
                  <String, dynamic>{'value': 5000})
              : null,
          child: const Text('色温 5000K'),
        ),
      ];
    }
    if (device is DemoDevice) {
      return <Widget>[
        FilledButton(
          onPressed: studio.isRunning
              ? () => notifier.sendCommand('led_on', const <String, dynamic>{})
              : null,
          child: const Text('LED 开'),
        ),
        const SizedBox(height: 6),
        FilledButton.tonal(
          onPressed: studio.isRunning
              ? () => notifier.sendCommand('led_off', const <String, dynamic>{})
              : null,
          child: const Text('LED 关'),
        ),
      ];
    }
    return const <Widget>[];
  }
}
