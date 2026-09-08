import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:myhome/studio/split_pane.dart';

/// 左右分栏容器拖拽测试。
void main() {
  Future<void> pumpPane(WidgetTester tester, {double width = 800}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              height: 400,
              child: const SplitPane(
                left: ColoredBox(
                  key: ValueKey<String>('left'),
                  color: Colors.blue,
                  child: SizedBox.expand(),
                ),
                right: ColoredBox(
                  key: ValueKey<String>('right'),
                  color: Colors.red,
                  child: SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('默认左右各半', (tester) async {
    await pumpPane(tester);

    final left = tester.getSize(find.byKey(const ValueKey<String>('left')));
    final right = tester.getSize(find.byKey(const ValueKey<String>('right')));

    expect(left.width, closeTo(400, 1)); // 800 * 50%
    expect(right.width, closeTo(395, 1)); // 剩余空间减去 5px 分割线
  });

  testWidgets('向右拖分割线 → 左侧变宽', (tester) async {
    await pumpPane(tester);
    final before = tester.getSize(find.byKey(const ValueKey<String>('left'))).width;

    await tester.drag(find.byKey(SplitPane.dividerKey), const Offset(100, 0));
    await tester.pump();

    final after = tester.getSize(find.byKey(const ValueKey<String>('left'))).width;
    expect(after, greaterThan(before));
  });

  testWidgets('拖到极限被钳制在 20%-80%', (tester) async {
    await pumpPane(tester);
    final total = 800.0;

    // 向右拖到底 → 左侧最多 80%
    await tester.drag(
      find.byKey(SplitPane.dividerKey),
      const Offset(1000, 0),
    );
    await tester.pump();
    var left = tester.getSize(find.byKey(const ValueKey<String>('left'))).width;
    expect(left, closeTo(total * 0.8, 1));

    // 向左拖到底 → 左侧最少 20%
    await tester.drag(
      find.byKey(SplitPane.dividerKey),
      const Offset(-1000, 0),
    );
    await tester.pump();
    left = tester.getSize(find.byKey(const ValueKey<String>('left'))).width;
    expect(left, closeTo(total * 0.2, 1));
  });
}
