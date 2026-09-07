import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:myhome/app/app.dart';
import 'package:myhome/ble/ble_scanner.dart';
import 'package:myhome/providers/ble_provider.dart';

/// 测试用假扫描器。
///
/// 不构造 FlutterReactiveBle 实例：FRB 构造函数内部会启动异步状态轮询
/// Timer，在 widget 测试结束时仍然挂起会导致测试失败（测试宿主机 macOS
/// 上 `Platform.isMacOS == true`，会进入真实实现分支）。
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

void main() {
  testWidgets('App 启动后显示设备扫描页', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bleScannerProvider.overrideWithValue(FakeBleScanner()),
        ],
        child: const MyApp(),
      ),
    );
    await tester.pump();

    expect(find.text('设备扫描'), findsOneWidget);
    expect(find.text('Mock 设备演示'), findsOneWidget);
  });
}
