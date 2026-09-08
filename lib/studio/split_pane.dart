import 'package:flutter/material.dart';

/// 左右分栏容器：中间分割线可拖拽调整左右比例。
///
/// 左侧占比限制在 20%–80%，且两侧各保留至少 120px。
class SplitPane extends StatefulWidget {
  const SplitPane({super.key, required this.left, required this.right});

  /// 分割线 Key (测试用)。
  static const Key dividerKey = ValueKey<String>('split-pane-divider');

  final Widget left;
  final Widget right;

  @override
  State<SplitPane> createState() => _SplitPaneState();
}

class _SplitPaneState extends State<SplitPane> {
  /// 左侧占比。
  double _leftFraction = 0.5;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final total = constraints.maxWidth;
        final leftWidth = (total * _leftFraction)
            .clamp(120.0, total > 240 ? total - 120.0 : total / 2);
        return Row(
          children: <Widget>[
            SizedBox(width: leftWidth, child: widget.left),
            _divider(context, total, leftWidth),
            Expanded(child: widget.right),
          ],
        );
      },
    );
  }

  Widget _divider(BuildContext context, double total, double leftWidth) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        key: SplitPane.dividerKey,
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) => setState(() {
          _leftFraction =
              ((leftWidth + details.delta.dx) / total).clamp(0.2, 0.8);
        }),
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
