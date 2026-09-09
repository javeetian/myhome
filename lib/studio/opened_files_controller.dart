import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

/// 已打开文件状态 (编辑器标签栏)。
class OpenedFilesState {
  const OpenedFilesState({required this.paths, this.active});

  /// 已打开文件路径 (标签顺序)。
  final List<String> paths;

  /// 当前激活的标签 (null = 无)。
  final String? active;
}

/// 已打开文件控制器：文件树点击 → open；标签切换 / 关闭。
class OpenedFilesController extends Notifier<OpenedFilesState> {
  @override
  OpenedFilesState build() => const OpenedFilesState(paths: <String>[]);

  /// 清空全部标签 (设备停止/切换时)。
  void reset() => state = const OpenedFilesState(paths: <String>[]);

  /// 设备启动时重置并自动打开 UI 入口 (ui/index.html 存在时)。
  void resetAndOpen({required String root}) {
    final entry = File(p.join(root, 'ui', 'index.html'));
    if (entry.existsSync()) {
      state = OpenedFilesState(paths: <String>[entry.path], active: entry.path);
    } else {
      reset();
    }
  }

  /// 打开文件 (已打开则仅切换激活)。
  void open(String path) {
    final paths = List<String>.of(state.paths);
    if (!paths.contains(path)) {
      paths.add(path);
    }
    state = OpenedFilesState(paths: paths, active: path);
  }

  /// 关闭标签；关闭激活标签时激活最后一个剩余标签。
  void close(String path) {
    final paths = List<String>.of(state.paths)..remove(path);
    final active = state.active == path
        ? (paths.isEmpty ? null : paths.last)
        : state.active;
    state = OpenedFilesState(paths: paths, active: active);
  }

  /// 切换激活标签。
  void setActive(String path) =>
      state = OpenedFilesState(paths: state.paths, active: path);

  /// 下一个标签 (循环)。
  void nextTab() {
    final paths = state.paths;
    final active = state.active;
    if (paths.length < 2 || active == null) {
      return;
    }
    final index = (paths.indexOf(active) + 1) % paths.length;
    setActive(paths[index]);
  }

  /// 上一个标签 (循环)。
  void prevTab() {
    final paths = state.paths;
    final active = state.active;
    if (paths.length < 2 || active == null) {
      return;
    }
    final index = (paths.indexOf(active) - 1 + paths.length) % paths.length;
    setActive(paths[index]);
  }
}

final openedFilesProvider =
    NotifierProvider<OpenedFilesController, OpenedFilesState>(
  OpenedFilesController.new,
);

/// 中心栏拆分视图开关：true = 左源码 | 右 WebView 预览。
class SplitPreviewController extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

final splitPreviewProvider =
    NotifierProvider<SplitPreviewController, bool>(SplitPreviewController.new);
