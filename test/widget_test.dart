import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:myhome/app/app.dart';
import 'package:myhome/l10n/app_localizations.dart';
import 'package:myhome/ui/pages/home_page.dart';

void main() {
  testWidgets('App 启动后显示主界面 (设置/添加/空状态)', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await tester.pumpAndSettle();

    final l10n =
        AppLocalizations.of(tester.element(find.byType(HomePage)))!;
    // 标题
    expect(find.text('MyHome'), findsOneWidget);
    // 左上设置、右上添加
    expect(find.byIcon(Icons.settings), findsOneWidget);
    // 空状态：右上角 + 中央大按钮两个加号
    expect(find.byIcon(Icons.add), findsNWidgets(2));
    expect(find.text(l10n.homeEmptyHint), findsOneWidget);
  });
}
