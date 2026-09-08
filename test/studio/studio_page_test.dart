import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:myhome/studio/studio_app.dart';

/// Device Studio 页面 (WORK_V3 §22/§30) 渲染测试。
void main() {
  testWidgets('idle 状态渲染三栏：设备列表 / 提示 / Inspector / Console', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: StudioApp()));
    await tester.pump();

    // 标题与三栏
    expect(find.text('Device Studio'), findsOneWidget);
    expect(find.text('设备'), findsOneWidget);
    expect(find.text('Inspector'), findsOneWidget);
    expect(find.text('Protocol Console'), findsOneWidget);

    // 设备列表：两个模拟设备
    expect(find.text('Smart Light (L100)'), findsOneWidget);
    expect(find.text('Demo Light'), findsOneWidget);

    // 空闲提示
    expect(find.text('选择左侧设备开始模拟'), findsOneWidget);

    // Inspector 占位字段
    expect(find.text('Device ID'), findsOneWidget);
    expect(find.text('UI Version'), findsOneWidget);
    expect(find.text('State'), findsOneWidget);
    expect(find.text('Command'), findsOneWidget);
  });
}
