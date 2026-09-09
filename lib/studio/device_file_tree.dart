import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// 设备目录文件树 (VS Code Explorer 风格, WORK_V3 §30 扩展)。
///
/// 目录在前递归展开；文件按扩展名配图标；
/// 点击文件回调 [onFileTap] (Studio 中为编辑器打开标签)。
class DeviceFileTree extends StatefulWidget {
  const DeviceFileTree({super.key, required this.deviceDir, this.onFileTap});

  /// 设备源目录 (null = 无目录，显示占位提示)。
  final String? deviceDir;

  /// 文件点击回调 (null = 不可点击)。
  final void Function(String path)? onFileTap;

  @override
  State<DeviceFileTree> createState() => _DeviceFileTreeState();
}

class _DeviceFileTreeState extends State<DeviceFileTree> {
  /// 手动刷新计数 (文件变化后点刷新重建)。
  int _tick = 0;

  @override
  Widget build(BuildContext context) {
    final dir = widget.deviceDir;
    final root = dir != null && Directory(dir).existsSync() ? dir : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
          child: Row(
            children: <Widget>[
              Text('文件树', style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh, size: 16),
                tooltip: '刷新文件树',
                visualDensity: VisualDensity.compact,
                onPressed: root == null ? null : () => setState(() => _tick++),
              ),
            ],
          ),
        ),
        Expanded(
          child: root == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '启动设备后显示其目录',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                )
              : ListView(
                  key: ValueKey<int>(_tick),
                  children: _buildEntries(root, 0),
                ),
        ),
      ],
    );
  }

  List<Widget> _buildEntries(String dirPath, int depth) {
    final entries = Directory(dirPath).listSync().toList()
      ..sort((a, b) {
        final aDir = a is Directory;
        final bDir = b is Directory;
        if (aDir != bDir) {
          return aDir ? -1 : 1; // 目录在前
        }
        return p.basename(a.path).compareTo(p.basename(b.path));
      });
    return <Widget>[
      for (final entity in entries)
        if (entity is Directory)
          _folderTile(entity.path, depth)
        else
          _fileTile(entity.path, depth),
    ];
  }

  Widget _folderTile(String path, int depth) {
    final name = p.basename(path);
    return Padding(
      padding: EdgeInsets.only(left: depth * 12.0),
      child: ExpansionTile(
        key: PageStorageKey<String>('dir-$path'),
        dense: true,
        visualDensity: VisualDensity.compact,
        leading: const Icon(Icons.folder_outlined, size: 16),
        title: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
        children: _buildEntries(path, depth + 1),
      ),
    );
  }

  Widget _fileTile(String path, int depth) {
    final name = p.basename(path);
    return Padding(
      padding: EdgeInsets.only(left: depth * 12.0 + 16.0),
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding: EdgeInsets.zero,
        leading: Icon(_fileIcon(name), size: 14),
        title: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
        onTap: widget.onFileTap == null
            ? null
            : () => widget.onFileTap!(path),
      ),
    );
  }

  IconData _fileIcon(String name) {
    if (name.endsWith('.dart')) return Icons.code;
    if (name.endsWith('.yaml') || name.endsWith('.yml')) return Icons.settings;
    if (name.endsWith('.html')) return Icons.language;
    if (name.endsWith('.css')) return Icons.palette_outlined;
    if (name.endsWith('.js')) return Icons.javascript;
    if (name.endsWith('.json')) return Icons.data_object;
    if (name.endsWith('.c') || name.endsWith('.h')) return Icons.memory;
    if (name.endsWith('.pkg') || name.endsWith('.gz') || name.endsWith('.zip')) {
      return Icons.archive_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }
}
