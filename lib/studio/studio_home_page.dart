import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/app_log.dart';
import '../device/defined_virtual_device.dart';
import '../device/device_definition.dart';
import '../device/protocol_device.dart';
import '../device/virtual_light.dart';
import '../simulator/fault_injector.dart';
import '../ui_runtime/webview_host.dart';
import 'device_file_tree.dart';
import 'device_yaml_form.dart';
import 'device_list_controller.dart';
import 'editor_settings.dart';
import 'opened_files_controller.dart';
import 'source_editor.dart';
import 'split_pane.dart';
import 'studio_controller.dart';

/// Device Studio 主页面 (WORK_V3 §22/§30)：
/// 四栏布局 —— 设备列表 | 文件树 | UI 预览 + Protocol Console | Inspector。
/// 栏间分割线可拖拽调整宽度。
class StudioHomePage extends ConsumerStatefulWidget {
  const StudioHomePage({super.key});

  /// 拖拽分割线 Key (测试用)。
  static const Key deviceListDividerKey = ValueKey<String>('divider-device-list');
  static const Key fileTreeDividerKey = ValueKey<String>('divider-file-tree');
  static const Key inspectorDividerKey = ValueKey<String>('divider-inspector');

  @override
  ConsumerState<StudioHomePage> createState() => _StudioHomePageState();
}

class _StudioHomePageState extends ConsumerState<StudioHomePage> {
  double _deviceListWidth = 220;
  double _fileTreeWidth = 200;
  double _inspectorWidth = 260;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: <Widget>[
          const _StudioMenuBar(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SizedBox(
                  width: _deviceListWidth,
                  child: const _DeviceListPanel(),
                ),
                _PanelDivider(
                  key: StudioHomePage.deviceListDividerKey,
                  onDrag: (delta) => setState(() {
                    _deviceListWidth =
                        (_deviceListWidth + delta).clamp(120.0, 480.0);
                  }),
                ),
                // 文件树：与设备列表并排 (当前设备目录)
                SizedBox(
                  width: _fileTreeWidth,
                  child: Consumer(
                    builder: (context, ref, _) => DeviceFileTree(
                      deviceDir: ref.watch(studioControllerProvider).deviceDir,
                      onFileTap: (path) =>
                          ref.read(openedFilesProvider.notifier).open(path),
                    ),
                  ),
                ),
                _PanelDivider(
                  key: StudioHomePage.fileTreeDividerKey,
                  onDrag: (delta) => setState(() {
                    _fileTreeWidth =
                        (_fileTreeWidth + delta).clamp(120.0, 480.0);
                  }),
                ),
                const Expanded(child: _CenterPanel()),
                _PanelDivider(
                  key: StudioHomePage.inspectorDividerKey,
                  // 拖动向右 → Inspector 变窄
                  onDrag: (delta) => setState(() {
                    _inspectorWidth =
                        (_inspectorWidth - delta).clamp(180.0, 480.0);
                  }),
                ),
                SizedBox(
                  width: _inspectorWidth,
                  child: const _InspectorPanel(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 顶部菜单栏：文件 / 设置 / 帮助。
class _StudioMenuBar extends ConsumerWidget {
  const _StudioMenuBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studio = ref.watch(studioControllerProvider);
    final controller = ref.read(studioControllerProvider.notifier);
    final opened = ref.watch(openedFilesProvider);
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // 菜单栏行 (VSCode 风格)
          SizedBox(
            height: 30,
            child: Row(
              children: <Widget>[
                _MenuButton(
                  label: '文件',
                  entries: <(String, VoidCallback?)>[
                    ('新建设备', () => showCreateDeviceDialog(context, ref)),
                    (
                      '打开设备目录',
                      () async {
                        final error = await ref
                            .read(deviceListProvider.notifier)
                            .pickAndImport();
                        if (error != null && context.mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text(error)));
                        }
                      },
                    ),
                    ('断开设备', studio.isRunning ? controller.stop : null),
                    ('退出', () => exit(0)),
                  ],
                ),
                _MenuButton(
                  label: '编辑',
                  entries: <(String, VoidCallback?)>[
                    (
                      '关闭当前标签',
                      opened.active == null
                          ? null
                          : () => ref
                              .read(openedFilesProvider.notifier)
                              .close(opened.active!),
                    ),
                    ('下一个标签', () => ref.read(openedFilesProvider.notifier).nextTab()),
                    ('上一个标签', () => ref.read(openedFilesProvider.notifier).prevTab()),
                  ],
                ),
                _MenuButton(
                  label: '选择',
                  entries: <(String, VoidCallback?)>[
                    (
                      '复制当前文件路径',
                      opened.active == null
                          ? null
                          : () => Clipboard.setData(
                              ClipboardData(text: opened.active!),
                            ),
                    ),
                    (
                      '打开文件所在目录',
                      opened.active == null
                          ? null
                          : () => _openInExplorer(p.dirname(opened.active!)),
                    ),
                  ],
                ),
                _MenuButton(
                  label: '查看',
                  entries: <(String, VoidCallback?)>[
                    ('放大字体', () => ref.read(editorFontSizeProvider.notifier).increase()),
                    ('缩小字体', () => ref.read(editorFontSizeProvider.notifier).decrease()),
                    ('重置字体', () => ref.read(editorFontSizeProvider.notifier).reset()),
                    (
                      '拆分预览',
                      () => ref.read(splitPreviewProvider.notifier).toggle(),
                    ),
                    (
                      '显示 Protocol Console',
                      () => ref.read(showConsoleProvider.notifier).toggle(),
                    ),
                    (
                      '日志等级: ${controller.logLevel.name.toUpperCase()}',
                      () {
                        final levels = LogLevel.values;
                        final next = levels[
                            (levels.indexOf(controller.logLevel) + 1) %
                                levels.length];
                        controller.setLogLevel(next);
                      },
                    ),
                  ],
                ),
                _MenuButton(
                  label: '转到',
                  entries: <(String, VoidCallback?)>[
                    ('下一个标签', () => ref.read(openedFilesProvider.notifier).nextTab()),
                    ('上一个标签', () => ref.read(openedFilesProvider.notifier).prevTab()),
                    ('重载 UI 预览', studio.isRunning ? controller.reloadUi : null),
                  ],
                ),
                _MenuButton(
                  label: '运行',
                  entries: <(String, VoidCallback?)>[
                    (
                      '生成代码',
                      studio.deviceDir == null
                          ? null
                          : () async {
                              final error = await controller.generateCode();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      error ??
                                          '已生成 ui.pkg + Dart/C/模拟器代码 '
                                              '(generated/)',
                                    ),
                                  ),
                                );
                              }
                            },
                    ),
                    ('重置设备', studio.isRunning ? controller.reset : null),
                    ('断开', studio.isRunning ? controller.stop : null),
                    ('UI Hot Reload', controller.toggleUiWatch),
                  ],
                ),
                _MenuButton(
                  label: '帮助',
                  entries: <(String, VoidCallback?)>[
                    (
                      '关于 Device Studio',
                      () => showDialog<void>(
                        context: context,
                        builder: (context) => const AboutDialog(
                          applicationName: 'Device Studio',
                          applicationVersion: 'V3',
                          applicationLegalese:
                              'Device UI Platform — 设备 UI 开发平台\n'
                              '文档: docs/QUICKSTART.md',
                        ),
                      ),
                    ),
                    (
                      '快速上手文档',
                      () => showDialog<void>(
                        context: context,
                        builder: (context) => const AlertDialog(
                          title: Text('快速上手'),
                          content: Text(
                            'docs/QUICKSTART.md\n'
                            '跑 Studio / 设计 UI / 生成固件代码',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 工具栏行
          SizedBox(
            height: 30,
            child: Row(
              children: <Widget>[
                const SizedBox(width: 4),
                // 生成代码 (当前设备, 与运行菜单一致)
                IconButton(
                  icon: const Icon(Icons.bolt, size: 16),
                  tooltip: '生成代码',
                  visualDensity: VisualDensity.compact,
                  onPressed: studio.deviceDir == null
                      ? null
                      : () async {
                          final error = await controller.generateCode();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  error ??
                                      '已生成 ui.pkg + Dart/C/模拟器代码 (generated/)',
                                ),
                              ),
                            );
                          }
                        },
                ),
                // 设备控制 (未启动时禁用置灰)
                IconButton(
                  icon: const Icon(Icons.refresh, size: 16),
                  tooltip: '重置设备',
                  visualDensity: VisualDensity.compact,
                  onPressed: studio.isRunning ? controller.reset : null,
                ),
                IconButton(
                  icon: const Icon(Icons.stop, size: 16),
                  tooltip: '断开',
                  visualDensity: VisualDensity.compact,
                  onPressed: studio.isRunning ? controller.stop : null,
                ),
                // 编辑器字体缩放
                IconButton(
                  icon: const Icon(Icons.text_decrease, size: 16),
                  tooltip: '缩小字体',
                  visualDensity: VisualDensity.compact,
                  onPressed: () =>
                      ref.read(editorFontSizeProvider.notifier).decrease(),
                ),
                Consumer(
                  builder: (context, ref, _) => Text(
                    '${ref.watch(editorFontSizeProvider).round()}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.text_increase, size: 16),
                  tooltip: '放大字体',
                  visualDensity: VisualDensity.compact,
                  onPressed: () =>
                      ref.read(editorFontSizeProvider.notifier).increase(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 在系统资源管理器中打开目录 (Windows Explorer / macOS Finder)。
void _openInExplorer(String path) {
  if (Platform.isWindows) {
    Process.run('explorer', <String>[path]);
  } else if (Platform.isMacOS) {
    Process.run('open', <String>[path]);
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({required this.label, required this.entries});

  final String label;

  /// (显示文本, 动作)；动作 null = 禁用项。
  final List<(String, VoidCallback?)> entries;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: '',
      position: PopupMenuPosition.under,
      onSelected: (index) => entries[index].$2?.call(),
      itemBuilder: (context) => <PopupMenuItem<int>>[
        for (var i = 0; i < entries.length; i++)
          PopupMenuItem<int>(
            value: i,
            enabled: entries[i].$2 != null,
            height: 32,
            child: Text(entries[i].$1, style: const TextStyle(fontSize: 13)),
          ),
      ],
      child: _MenuLabel(label),
    );
  }
}

/// 菜单栏标签样式。
class _MenuLabel extends StatelessWidget {
  const _MenuLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Text(text, style: const TextStyle(fontSize: 13)),
    );
  }
}

/// 可拖拽分割线：5px 命中区 + 1px 视觉线，拖动调整相邻栏宽度。
class _PanelDivider extends StatelessWidget {
  const _PanelDivider({super.key, required this.onDrag});

  /// 拖拽回调：delta 为水平位移 (向右为正)。
  final void Function(double delta) onDrag;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
        child: SizedBox(
          width: 5,
          child: Center(
            child: Container(
              width: 1,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
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

    return Column(
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
          child: ReorderableListView(
            padding: const EdgeInsets.all(8),
            buildDefaultDragHandles: false,
            onReorderItem: (oldIndex, newIndex) =>
                ref.read(deviceListProvider.notifier).moveItem(
                      oldIndex,
                      newIndex,
                    ),
            children: <Widget>[
              for (final info in devices)
                ReorderableDelayedDragStartListener(
                  key: ValueKey<String>(info.dirName),
                  index: devices.indexOf(info),
                  child: _deviceDirCard(context, ref, studio, info),
                ),
            ],
          ),
        ),
      ],
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
    final definition = info.definition;
    final notifier = ref.read(studioControllerProvider.notifier);
    if (definition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${info.dirName}: device.yaml 无效')),
      );
      return;
    }
    // UI 包：现场打包该设备的 ui 目录 (产物存在则直读)
    final uiDir = '${info.dirPath}/ui';
    final outPkg = '${info.dirPath}/build/ui.pkg';
    final pkg = await notifier.packUiDir(uiDir, outPkg);
    // smart_light 用带温度传感器行为的专用模拟器；
    // 其余设备由 device.yaml 驱动的通用模拟器运行 (定义驱动, WORK_V3)。
    final ProtocolDevice device = definition.id == 'smart_light'
        ? VirtualLight(uiPkgBytes: pkg)
        : DefinedVirtualDevice(definition, uiPkgBytes: pkg);
    final ok = await notifier.start(device, deviceDir: info.dirPath);
    if (ok) {
      // UI Hot Reload (Phase 37)：源目录变化 → 自动重打包重载
      notifier.startUiWatch(uiDir, outPkg);
    }
  }

  Future<void> _onListAction(
    BuildContext context,
    WidgetRef ref,
    _ListAction action,
  ) async {
    switch (action) {
      case _ListAction.create:
        await showCreateDeviceDialog(context, ref);
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
}

/// 新建设备弹窗 (菜单栏与设备列表共用)。
Future<void> showCreateDeviceDialog(BuildContext context, WidgetRef ref) async {
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

/// 中栏：编辑器标签栏 + 源码 / UI 预览 (WORK_V3 §24/§30 扩展)。
/// 右上角按钮切换拆分视图：左源码 | 右 WebView 预览。
class _CenterPanel extends ConsumerWidget {
  const _CenterPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studio = ref.watch(studioControllerProvider);
    final opened = ref.watch(openedFilesProvider);
    final split = ref.watch(splitPreviewProvider);

    return Column(
      children: <Widget>[
        _EditorTabBar(opened: opened, split: split),
        Expanded(
          child: !studio.isRunning
              ? Center(
                  child: Text(
                    studio.error != null
                        ? '启动失败: ${studio.error}'
                        : '选择左侧设备开始模拟',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                )
              : _buildContent(
                  ref,
                  studio,
                  opened,
                  split,
                  fontSize: ref.watch(editorFontSizeProvider),
                ),
        ),
        if (ref.watch(showConsoleProvider)) ...<Widget>[
          const Divider(height: 1),
          _ProtocolConsole(lines: studio.protocolLog),
        ],
      ],
    );
  }

  Widget _buildContent(
    WidgetRef ref,
    StudioState studio,
    OpenedFilesState opened,
    bool split, {
    required double fontSize,
  }) {
    final Widget editor;
    if (opened.active == null) {
      editor = const Center(child: Text('从左侧文件树选择文件'));
    } else if (ref.watch(editorViewControllerProvider) == EditorView.ui &&
        p.basename(opened.active!) == 'device.yaml') {
      // UI 视图：device.yaml 可视化表单
      editor = DeviceYamlForm(
        key: ValueKey<String>('${opened.active}#${opened.revision}'),
        path: opened.active!,
      );
    } else {
      editor = SourceEditor(
        key: ValueKey<String>('${opened.active}#${opened.revision}'),
        path: opened.active!,
        fontSize: fontSize,
      );
    }
    if (!split) {
      return editor;
    }
    final webview = studio.entryUrl != null
        ? WebViewHost(
            // reloadCount 变化 → 重建重载 (UI Hot Reload, Phase 37)
            key: ValueKey<String>('${studio.entryUrl}#${studio.reloadCount}'),
            url: studio.entryUrl!,
          )
        : const SizedBox.shrink();
    return SplitPane(left: editor, right: webview);
  }
}

/// 编辑器标签栏：已打开文件标签 + 右上角拆分按钮。
class _EditorTabBar extends ConsumerWidget {
  const _EditorTabBar({required this.opened, required this.split});

  final OpenedFilesState opened;
  final bool split;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 30,
      child: Row(
        children: <Widget>[
          Expanded(
            child: opened.paths.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      '未打开文件',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.grey),
                    ),
                  )
                : ListView(
                    scrollDirection: Axis.horizontal,
                    children: <Widget>[
                      for (final path in opened.paths)
                        _tab(context, ref, path, active: path == opened.active),
                    ],
                  ),
          ),
          // 视图切换：源码 / UI 表单 (device.yaml 支持可视化编辑)
          // Flexible + FittedBox：中间栏极窄时按钮区自动缩放，避免溢出
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
          _toolButton(
            context,
            ref,
            icon: Icons.code,
            tooltip: '源码视图',
            active: ref.watch(editorViewControllerProvider) == EditorView.source,
            onTap: () => ref
                .read(editorViewControllerProvider.notifier)
                .set(EditorView.source),
          ),
          _toolButton(
            context,
            ref,
            icon: Icons.list_alt,
            tooltip: _supportsUiView(opened.active)
                ? 'UI 视图 (可视化编辑)'
                : '此文件类型不支持 UI 视图',
            active: ref.watch(editorViewControllerProvider) == EditorView.ui,
            onTap: _supportsUiView(opened.active)
                ? () => ref
                    .read(editorViewControllerProvider.notifier)
                    .set(EditorView.ui)
                : null,
          ),
          _toolButton(
            context,
            ref,
            icon: split ? Icons.vertical_split : Icons.splitscreen,
            tooltip: split ? '合并视图' : '拆分视图：源码 | 预览',
            active: split,
            onTap: () => ref.read(splitPreviewProvider.notifier).toggle(),
          ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 紧凑工具栏按钮 (固定 22px 宽，避免 IconButton 默认 fixedSize)。
  Widget _toolButton(
    BuildContext context,
    WidgetRef ref, {
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
    bool active = false,
  }) {
    final primary = Theme.of(context).colorScheme.primary;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 22,
          height: 30,
          child: Icon(
            icon,
            size: 15,
            // 禁用置灰；激活高亮
            color: onTap == null
                ? Colors.grey
                : (active ? primary : null),
          ),
        ),
      ),
    );
  }

  /// 支持 UI 表单视图的文件类型。
  static bool _supportsUiView(String? path) =>
      path != null && p.basename(path) == 'device.yaml';

  Widget _tab(BuildContext context, WidgetRef ref, String path,
      {required bool active}) {
    final name = p.basename(path);
    return InkWell(
      onTap: () => ref.read(openedFilesProvider.notifier).setActive(path),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              width: 2,
              color: active
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(name, style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 4),
            InkWell(
              onTap: () =>
                  ref.read(openedFilesProvider.notifier).close(path),
              child: const Icon(Icons.close, size: 12),
            ),
          ],
        ),
      ),
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

    return ListView(
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
    );
  }

  Widget _row(BuildContext context, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: <Widget>[
            Flexible(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value,
                style: Theme.of(context).textTheme.bodyMedium,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      );

  List<Widget> _commandButtons(BuildContext context, WidgetRef ref) {
    final studio = ref.watch(studioControllerProvider);
    final device = studio.device;
    final notifier = ref.read(studioControllerProvider.notifier);
    // 定义驱动 (WORK_V3)：命令按钮完全由 device.yaml 生成，
    // 任何设备 (VirtualLight / DefinedVirtualDevice) 都不写死命令。
    final definition = switch (device) {
      VirtualLight _ => VirtualLight.builtInDefinition,
      DefinedVirtualDevice d => d.definition,
      _ => null,
    };
    if (definition != null) {
      final state = studio.currentState?.state ?? const <String, dynamic>{};
      final buttons = <Widget>[];
      for (final command in definition.commands) {
        // 状态键与模拟器约定一致：末段去掉 set_ 前缀
        final lastSegment = command.name.split('.').last;
        final stateKey = lastSegment.startsWith('set_')
            ? lastSegment.substring(4)
            : lastSegment;
        final params = <String, dynamic>{
          for (final entry in command.params.entries)
            entry.key: _defaultParamValue(entry.value, state[stateKey]),
        };
        // bool 状态键：按钮文案随当前状态变化 (开 power / 关 power)
        final isBoolState =
            definition.state[stateKey]?.type == ValueType.boolType;
        final label = isBoolState
            ? (state[stateKey] == true ? '关 $stateKey' : '开 $stateKey')
            : stateKey;
        buttons
          ..add(FilledButton(
            onPressed: studio.isRunning
                ? () => notifier.sendCommand(command.name, params)
                : null,
            child: Text(label),
          ))
          ..add(const SizedBox(height: 6));
      }
      return buttons;
    }
    return const <Widget>[];
  }

  /// 命令参数默认值：bool → 取反当前值；数值 → 定义范围中间值。
  Object _defaultParamValue(ParamDefinition def, Object? current) {
    switch (def.type) {
      case ValueType.boolType:
        return !(current == true);
      case ValueType.uint8:
      case ValueType.uint16:
      case ValueType.int32:
        return ((def.min ?? 0) + (def.max ?? 100)) ~/ 2;
      case ValueType.float:
        return ((def.min ?? 0) + (def.max ?? 1)).toDouble() / 2;
      case ValueType.string:
        return '';
    }
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
