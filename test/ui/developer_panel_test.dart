import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:myhome/device/connection_phase.dart';
import 'package:myhome/device/device_session.dart';
import 'package:myhome/l10n/app_localizations.dart';
import 'package:myhome/providers/device_session_provider.dart';
import 'package:myhome/ui/pages/developer_panel.dart';

/// 测试用会话控制器：固定返回一个未连接客户端的快照。
class _FakeSessionController extends DeviceSessionController {
  @override
  DeviceSession build() => const DeviceSession(
        phase: ConnectionPhase.connected,
        deviceId: 'dev-1',
        error: null,
      );
}

/// Developer Mode 面板 (WORK_V2 §33) 测试。
void main() {
  testWidgets('面板渲染设备信息与统计字段', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceSessionProvider.overrideWith(_FakeSessionController.new),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: DeveloperPanel()),
        ),
      ),
    );
    await tester.pump();

    // 文案断言走 AppLocalizations，避免与测试宿主机语言耦合。
    final l10n =
        AppLocalizations.of(tester.element(find.byType(DeveloperPanel)))!;
    expect(find.text(l10n.devPanelTitle), findsOneWidget);
    expect(find.text(l10n.devDeviceId), findsOneWidget);
    expect(find.text('dev-1'), findsOneWidget);
    expect(find.text(l10n.devConnectionState), findsOneWidget);
    expect(find.text(l10n.phaseConnected), findsOneWidget);
    expect(find.text(l10n.devProtocolVersion), findsOneWidget);
    expect(find.text(l10n.devTxBytes), findsOneWidget);
    expect(find.text(l10n.devRxBytes), findsOneWidget);
    expect(find.text(l10n.devRetries), findsOneWidget);
    expect(find.text(l10n.devLatencyP50), findsOneWidget);
    expect(find.text(l10n.devLatencyP95), findsOneWidget);
    expect(find.text(l10n.devLatencyP99), findsOneWidget);
    expect(find.text(l10n.devLastError), findsOneWidget);
    // 无 client → 统计显示占位 (TX/RX/重试/命令数 四个 0；多个字段显示 -)
    expect(find.text('0'), findsNWidgets(4));
    expect(find.text('-'), findsAtLeastNWidgets(6));
  });
}
