import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ble/ble_scanner.dart';
import '../ble/ble_transport.dart';
import '../ble/reactive_ble_peripheral.dart';
import '../ble/reactive_ble_transport.dart';

/// BLE 扫描器单例。
final bleScannerProvider = Provider<BleScanner>((ref) {
  final scanner = BleScanner();
  ref.onDispose(scanner.dispose);
  return scanner;
});

/// 字节级 BLE 传输 (WORK_V2 §12.3 bleTransportProvider)。
///
/// 懒构造：仅在实际连接设备时读取；不支持平台 (web 等) 读取即抛
/// [UnsupportedError] —— 扫描页不读取本 provider，web 预览不受影响。
/// 类型为抽象 [BleTransport]，测试可 override 注入 Fake。
final bleTransportProvider = Provider<BleTransport>((ref) {
  if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
    throw UnsupportedError('当前平台不支持 BLE');
  }
  final peripheral = ReactiveBlePeripheral(FlutterReactiveBle());
  final transport = ReactiveBleTransport(peripheral: peripheral);
  ref.onDispose(transport.dispose);
  return transport;
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
