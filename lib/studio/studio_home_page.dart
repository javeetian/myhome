import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device/demo_device.dart';
import '../device/virtual_light.dart';
import '../simulator/fault_injector.dart';
import '../ui_runtime/webview_host.dart';
import 'device_list_controller.dart';
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
/// 列表头部 ⋮：新建 / 打开设备目录；每张设备卡片左上角 ⋮：移除 / 删除。
class _DeviceListPanel extends ConsumerWidget {
  const _DeviceListPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studio = ref.watch(studioControllerProvider);
    final devices = ref.watch(deviceListProvider);

    return SizedBox(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
            child: Row(
              children: <Widget>[
                Text('设备', style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                PopupMenuButton<_ListAction>(
                  icon: const Icon(Icons.more_vert, size: 18),
                  tooltip: '设备列表操作',
                  onSelected: (action) => _onListAction(context, ref, action),
                  itemBuilder: (context) => const <PopupMenuEntry<_ListAction>>[
                    PopupMenuItem<_ListAction>(
                      value: _ListAction.create,
                      child: Row(
                        children: <Widget>[
                          Icon(Icons.add_box_outlined, size: 18),
                          SizedBox(width: 8),
                          Text('新建设备'),
                        ],
                      ),
                    ),
                    PopupMenuItem<_ListAction>(
                      value: _ListAction.open,
                      child: Row(
                        children: <Widget>[
                          Icon(Icons.folder_open, size: 18),
                          SizedBox(width: 8),
                          Text('打开设备目录'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: <Widget>[
                _demoLightCard(context, ref, studio),
                for (final info in devices)
                  _deviceDirCard(context, ref, studio, info),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 内置 Demo Light 卡片 (无设备目录，不提供移除/删除)。
  Widget _demoLightCard(BuildContext context, WidgetRef ref, StudioState studio) {
    final deviceId = DemoDevice().deviceId;
    return _deviceCard(
      context,
      ref,
      title: 'Demo Light',
      subtitle: '内置 UI 演示设备',
      deviceId: deviceId,
      isRunning: currentDeviceRunning(studio, deviceId),
      onStart: () => ref
          .read(studioControllerProvider.notifier)
          .start(DemoDevice()),
    );
  }

  /// devices/ 目录设备卡片：左上角 ⋮ → 移除 / 删除。
  Widget _deviceDirCard(
    BuildContext context,
    WidgetRef ref,
    StudioState studio,
    DeviceDirInfo info,
  ) {
    final definition = info.definition;
    final running =
        definition != null && currentDeviceRunning(studio, definition.id);
    final title = definition?.name ?? info.dirName;
    final subtitle = definition != null
        ? '${definition.model} · ${info.dirName}'
        : (info.error ?? 'device.yaml 无效');

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: definition != null && !running
            ? () => _startDirDevice(context, ref, info)
            : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 2, 8, 2),
          child: Row(
            children: <Widget>[
              PopupMenuButton<_DeviceAction>(
                icon: const Icon(Icons.more_vert, size: 18),
                tooltip: '设备操作',
                onSelected: (action) => _onDeviceAction(context, ref, info, action),
                itemBuilder: (context) =>
                    const <PopupMenuEntry<_DeviceAction>>[
                  PopupMenuItem<_DeviceAction>(
                    value: _DeviceAction.remove,
                    child: Text('从列表移除'),
                  ),
                  PopupMenuItem<_DeviceAction>(
                    value: _DeviceAction.delete,
                    child: Text(
                      '删除设备目录',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Icon(
                running
                    ? Icons.check_circle
                    : (definition != null
                        ? Icons.play_arrow
                        : Icons.warning_amber),
                size: 18,
                color: running
                    ? Colors.green
                    : (definition != null ? null : Colors.orange),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool currentDeviceRunning(StudioState studio, String deviceId) =>
      studio.device?.deviceId == deviceId && studio.isRunning;

  /// 启动目录设备：仅实现了模拟器的设备可启动 (当前 smart_light)。
  Future<void> _startDirDevice(
    BuildContext context,
    WidgetRef ref,
    DeviceDirInfo info,
  ) async {
    final notifier = ref.read(studioControllerProvider.notifier);
    if (!info.hasSimulator) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${info.definition?.name}: 尚无模拟器实现'),
        ),
      );
      return;
    }
    // 构建产物缺失时从源目录现场打包 (QUICKSTART §2 免前提)
    final pkg = await notifier.loadSmartLightPkg();
    final ok = await notifier.start(VirtualLight(uiPkgBytes: pkg));
    if (ok) {
      // UI Hot Reload (Phase 37)：源目录变化 → 自动重打包重载
      notifier.startUiWatch(
        StudioController.smartLightUiDir,
        StudioController.smartLightPkgPath,
      );
    }
  }

  Future<void> _onListAction(
    BuildContext context,
    WidgetRef ref,
    _ListAction action,
  ) async {
    switch (action) {
      case _ListAction.create:
        await _showCreateDeviceDialog(context, ref);
      case _ListAction.open:
        // 原生目录选择器 → 选中的设备目录加入列表
        final error =
            await ref.read(deviceListProvider.notifier).pickAndImport();
        if (error != null && context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(error)));
        }
    }
  }

  Future<void> _onDeviceAction(
    BuildContext context,
    WidgetRef ref,
    DeviceDirInfo info,
    _DeviceAction action,
  ) async {
    final notifier = ref.read(deviceListProvider.notifier);
    switch (action) {
      case _DeviceAction.remove:
        notifier.remove(info);
      case _DeviceAction.delete:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('删除设备 ${info.dirName}?'),
            content: Text('将删除目录 ${info.dirPath}，此操作不可恢复。'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('删除'),
              ),
            ],
          ),
        );
        if (confirmed == true) {
          notifier.delete(info);
        }
    }
  }

  /// 新建设备弹窗：填写设备 ID / 名称 / 型号 → `devices/<id>/`。
  Future<void> _showCreateDeviceDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final created = await showDialog<({String id, String name, String model})>(
      context: context,
      builder: (context) => const _CreateDeviceDialog(),
    );
    if (created == null || !context.mounted) {
      return;
    }
    final error = ref.read(deviceListProvider.notifier).createDevice(
          id: created.id,
          name: created.name,
          model: created.model,
        );
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
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

/// 列表头部 ⋮ 菜单动作。
enum _ListAction { create, open }

/// 设备卡片 ⋮ 菜单动作。
enum _DeviceAction { remove, delete }

/// 新建设备弹窗 (WORK_V3 §29 扩展)：`devices/<id>/device.yaml` 骨架。
class _CreateDeviceDialog extends StatefulWidget {
  const _CreateDeviceDialog();

  @override
  State<_CreateDeviceDialog> createState() => _CreateDeviceDialogState();
}

class _CreateDeviceDialogState extends State<_CreateDeviceDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _id = TextEditingController();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _model = TextEditingController();

  @override
  void dispose() {
    _id.dispose();
    _name.dispose();
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新建设备'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextFormField(
              controller: _id,
              autofocus: true,
              decoration: const InputDecoration(labelText: '设备 ID (目录名)'),
              validator: (value) {
                final v = value?.trim() ?? '';
                if (v.isEmpty) {
                  return '必填';
                }
                if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(v)) {
                  return '小写字母/数字/下划线，字母开头';
                }
                return null;
              },
            ),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: '名称'),
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? '必填' : null,
            ),
            TextFormField(
              controller: _model,
              decoration: const InputDecoration(labelText: '型号'),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('创建')),
      ],
    );
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    Navigator.pop(
      context,
      (
        id: _id.text.trim(),
        name: _name.text.trim(),
        model: _model.text.trim(),
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
              ? WebViewHost(
                  // reloadCount 变化 → 重建重载 (UI Hot Reload, Phase 37)
                  key: ValueKey<String>(
                      '${studio.entryUrl}#${studio.reloadCount}'),
                  url: studio.entryUrl!,
                )
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
          if (studio.faultInjector != null) ...<Widget>[
            const Divider(),
            _FaultInjectionPanel(
              key: ValueKey<FaultInjector>(studio.faultInjector!),
              injector: studio.faultInjector!,
            ),
          ],
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

/// Fault Injection 面板 (WORK_V3 §32)。
/// 局部状态管理滑块值，onChanged 同步注入器参数。
class _FaultInjectionPanel extends StatefulWidget {
  const _FaultInjectionPanel({super.key, required this.injector});

  final FaultInjector injector;

  @override
  State<_FaultInjectionPanel> createState() => _FaultInjectionPanelState();
}

class _FaultInjectionPanelState extends State<_FaultInjectionPanel> {
  double _loss = 0;
  double _delay = 0;
  double _dup = 0;
  double _crc = 0;

  @override
  Widget build(BuildContext context) {
    final injector = widget.injector;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Fault Injection', style: Theme.of(context).textTheme.titleSmall),
        _slider('丢包 %', _loss, (v) {
          setState(() => _loss = v);
          injector.txPacketLoss = v / 100;
        }),
        _slider('延迟 ms', _delay, (v) {
          setState(() => _delay = v);
          injector.txDelay = Duration(milliseconds: v.round());
        }, max: 500),
        _slider('重复 %', _dup, (v) {
          setState(() => _dup = v);
          injector.txDuplicateRate = v / 100;
        }),
        _slider('CRC 损坏 %', _crc, (v) {
          setState(() => _crc = v);
          injector.txCrcErrorRate = v / 100;
        }),
        const SizedBox(height: 6),
        FilledButton(
          onPressed: () => injector.disconnectOnNextWrite = true,
          child: const Text('注入断开 (下次写入)'),
        ),
        const SizedBox(height: 4),
        Text(
          '已注入: 丢${injector.injectedLoss} 重${injector.injectedDuplicate} '
          '坏${injector.injectedCrcError}',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }

  Widget _slider(String label, double value, ValueChanged<double> onChanged,
      {double max = 100}) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text('$label ${value.round()}', style: const TextStyle(fontSize: 11)),
        ),
        Expanded(
          flex: 2,
          child: Slider(
            value: value,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
