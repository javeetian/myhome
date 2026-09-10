import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:myhome/app/app.dart';
import 'package:myhome/ble/ble_scanner.dart';
import 'package:myhome/l10n/app_localizations.dart';
import 'package:myhome/providers/ble_provider.dart';
import 'package:myhome/ui/pages/home_page.dart';
import 'package:myhome/ui/pages/scan_page.dart';
import 'package:myhome/ui/pages/settings_page.dart';

/// 测试用假扫描器：避免构造 FlutterReactiveBle 实例
/// (其构造会启动异步状态轮询 Timer，widget 测试结束时仍挂起会导致失败)。
class FakeBleScanner extends BleScanner {
  @override
  Stream<BleStatus> get statusStream =>
      Stream<BleStatus>.value(BleStatus.unsupported);

  @override
  Stream<List<DiscoveredDevice>> get scanResults =>
      Stream<List<DiscoveredDevice>>.value(const <DiscoveredDevice>[]);

  @override
  Stream<bool> get isScanning => Stream<bool>.value(false);

  @override
  Future<void> startScan() async {}

  @override
  Future<void> stopScan() async {}

  @override
  void dispose() {}
}

/// 历史列表种子数据 (两条：真实 BLE + 演示设备)。
String seedHistory() => jsonEncode(<Map<String, Object?>>[
      <String, Object?>{
        'id': 'dev-1',
        'name': 'Light A',
        'kind': 'ble',
        'addedAt': '2026-09-10T10:00:00',
      },
      <String, Object?>{
        'id': 'smart_light',
        'name': 'Smart Light',
        'kind': 'demo',
        'addedAt': '2026-09-09T10:00:00',
      },
    ]);

Future<void> pumpHome(
  WidgetTester tester, {
  String? historyJson,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'device_history': ?historyJson,
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bleScannerProvider.overrideWithValue(FakeBleScanner()),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const HomePage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 主界面 (WORK_V3 手机 App) 测试。
void main() {
  testWidgets('有历史设备时显示卡片列表', (WidgetTester tester) async {
    await pumpHome(tester, historyJson: seedHistory());
    final l10n =
        AppLocalizations.of(tester.element(find.byType(HomePage)))!;

    // 两张卡片：名称 + 图标 (BLE 设备 / 演示设备)
    expect(find.text('Light A'), findsOneWidget);
    expect(find.text('Smart Light'), findsOneWidget);
    expect(find.byIcon(Icons.devices), findsOneWidget);
    expect(find.byIcon(Icons.lightbulb), findsOneWidget);
    // 副标题：最近连接时间 (含本地化前缀)
    expect(find.textContaining(l10n.lastConnected('')), findsNWidgets(2));
  });

  testWidgets('空状态显示中央大添加按钮，点击进入添加设备页', (WidgetTester tester) async {
    await pumpHome(tester);
    final l10n =
        AppLocalizations.of(tester.element(find.byType(HomePage)))!;

    expect(find.text(l10n.homeEmptyHint), findsOneWidget);
    await tester.tap(find.byIcon(Icons.add).last); // 中央大按钮
    await tester.pumpAndSettle();

    expect(find.byType(ScanPage), findsOneWidget);
    expect(find.text(l10n.demoCardTitle), findsOneWidget);
  });

  testWidgets('移除历史设备需确认', (WidgetTester tester) async {
    await pumpHome(tester, historyJson: seedHistory());
    final l10n =
        AppLocalizations.of(tester.element(find.byType(HomePage)))!;

    // 第一张卡片菜单 → 移除 → 确认
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.removeDevice).last);
    await tester.pumpAndSettle();
    // 确认对话框：取消不生效
    await tester.tap(find.widgetWithText(TextButton, l10n.cancel));
    await tester.pumpAndSettle();
    expect(find.text('Light A'), findsOneWidget);

    // 再次移除并确认 → 卡片消失
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.removeDevice).last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, l10n.removeDevice));
    await tester.pumpAndSettle();

    expect(find.text('Light A'), findsNothing);
    expect(find.text('Smart Light'), findsOneWidget);
  });

  testWidgets('设置页切换语言即时生效并持久化', (WidgetTester tester) async {
    // 用真实 MyApp：locale 由 localeProvider 驱动 (本地 MaterialApp 不接)。
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bleScannerProvider.overrideWithValue(FakeBleScanner()),
        ],
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();
    final l10n =
        AppLocalizations.of(tester.element(find.byType(HomePage)))!;

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.text(l10n.language), findsOneWidget);
    expect(find.text(l10n.theme), findsOneWidget);

    // 展开「语言」栏 → 选择简体中文
    await tester.tap(find.text(l10n.language));
    await tester.pumpAndSettle();
    await tester.tap(find.text('简体中文'));
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('语言'), findsOneWidget);
    expect(find.text('跟随系统'), findsOneWidget);

    // 持久化：SharedPreferences 里存了 zh
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_locale'), 'zh');

    // 返回主界面 → 文案已是中文
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('还没有设备，点击上方按钮添加'), findsOneWidget);
  });

  testWidgets('设置页切换主题：浅色/深色/跟随系统并持久化', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bleScannerProvider.overrideWithValue(FakeBleScanner()),
        ],
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();
    final l10n =
        AppLocalizations.of(tester.element(find.byType(HomePage)))!;

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();

    // 展开「主题」栏
    await tester.tap(find.text(l10n.theme));
    await tester.pumpAndSettle();
    expect(find.text(l10n.themeLight), findsOneWidget);
    expect(find.text(l10n.themeDark), findsOneWidget);

    Brightness brightness() =>
        Theme.of(tester.element(find.byType(SettingsPage))).brightness;
    final prefs = await SharedPreferences.getInstance();

    // 浅色
    await tester.tap(find.text(l10n.themeLight));
    await tester.pumpAndSettle();
    expect(brightness(), Brightness.light);
    expect(prefs.getString('app_theme_mode'), 'light');

    // 深色
    await tester.tap(find.text(l10n.themeDark));
    await tester.pumpAndSettle();
    expect(brightness(), Brightness.dark);
    expect(prefs.getString('app_theme_mode'), 'dark');

    // 跟随系统
    await tester.tap(find.text(l10n.followSystem));
    await tester.pumpAndSettle();
    expect(prefs.getString('app_theme_mode'), 'system');
  });
}
