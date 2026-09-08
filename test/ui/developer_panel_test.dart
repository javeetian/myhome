import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:myhome/device/connection_phase.dart';
import 'package:myhome/device/device_session.dart';
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
        child: const MaterialApp(home: Scaffold(body: DeveloperPanel())),
      ),
    );
    await tester.pump();

    expect(find.text('开发者模式 (§33)'), findsOneWidget);
    expect(find.text('设备 ID'), findsOneWidget);
    expect(find.text('dev-1'), findsOneWidget);
    expect(find.text('连接状态'), findsOneWidget);
    expect(find.text('connected'), findsOneWidget);
    expect(find.text('协议版本'), findsOneWidget);
    expect(find.text('TX 字节'), findsOneWidget);
    expect(find.text('RX 字节'), findsOneWidget);
    expect(find.text('重试次数'), findsOneWidget);
    expect(find.text('命令延迟 P50'), findsOneWidget);
    expect(find.text('命令延迟 P95'), findsOneWidget);
    expect(find.text('命令延迟 P99'), findsOneWidget);
    expect(find.text('最近错误'), findsOneWidget);
    // 无 client → 统计显示占位 (TX/RX/重试/命令数 四个 0；多个字段显示 -)
    expect(find.text('0'), findsNWidgets(4));
    expect(find.text('-'), findsAtLeastNWidgets(6));
  });
}
