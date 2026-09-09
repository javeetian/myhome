import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 编辑器字体大小 (菜单栏工具栏 A- / A+ 调整)。
class EditorFontSize extends Notifier<double> {
  static const double _default = 12;

  @override
  double build() => _default;

  void decrease() => state = (state - 1).clamp(8.0, 28.0);

  void increase() => state = (state + 1).clamp(8.0, 28.0);

  void reset() => state = _default;
}

final editorFontSizeProvider =
    NotifierProvider<EditorFontSize, double>(EditorFontSize.new);

/// Protocol Console 显示开关 (查看菜单)。
class ShowConsole extends Notifier<bool> {
  @override
  bool build() => true;

  void toggle() => state = !state;
}

final showConsoleProvider =
    NotifierProvider<ShowConsole, bool>(ShowConsole.new);
