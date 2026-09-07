import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:myhome/app/app.dart';

void main() {
  testWidgets('App 启动后显示设备扫描页', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await tester.pump();

    expect(find.text('设备扫描'), findsOneWidget);
    expect(find.text('Mock 设备演示'), findsOneWidget);
  });
}
