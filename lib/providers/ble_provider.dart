import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ble/ble_scanner.dart';

/// BLE 扫描器单例。
final bleScannerProvider = Provider<BleScanner>((ref) {
  final scanner = BleScanner();
  ref.onDispose(scanner.dispose);
  return scanner;
});

/// 扫描结果流。
final scanResultsProvider = StreamProvider(
  (ref) => ref.watch(bleScannerProvider).scanResults,
);

/// 蓝牙状态流。
final bleStatusProvider = StreamProvider(
  (ref) => ref.watch(bleScannerProvider).statusStream,
);

/// 扫描进行中状态流。
final isScanningProvider = StreamProvider(
  (ref) => ref.watch(bleScannerProvider).isScanning,
);
