import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

/// BLE 扫描器：flutter_reactive_ble 的薄封装。
///
/// FRB 的特性：停止扫描 = 取消流订阅。因此这里维护自己的订阅句柄与扫描状态流。
///
/// 注意：FRB 仅支持 Android / iOS。其余平台 (含 web 与测试宿主环境)
/// 不构造 FRB 实例 —— 其构造函数内部会异步初始化并产生无法同步捕获的错误。
/// 必须先用 kIsWeb 判断：web 上 dart:io 的 Platform 反映的是浏览器宿主
/// 操作系统，直接判断会误入真实分支。
class BleScanner {
  FlutterReactiveBle? _ble;

  /// 平台是否支持 BLE。
  bool get _isSupported {
    if (_ble != null) {
      return true;
    }
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return false;
    }
    _ble = FlutterReactiveBle();
    return true;
  }

  /// 已发现的设备 (按 id 去重)。
  final Map<String, DiscoveredDevice> _seen = <String, DiscoveredDevice>{};

  final StreamController<List<DiscoveredDevice>> _results =
      StreamController<List<DiscoveredDevice>>.broadcast();

  final StreamController<bool> _scanning = StreamController<bool>.broadcast();

  StreamSubscription<DiscoveredDevice>? _sub;
  Timer? _timer;

  /// 扫描结果流：每次发现新设备时推送完整列表快照。
  Stream<List<DiscoveredDevice>> get scanResults => _results.stream;

  /// 蓝牙状态流 (ready / poweredOff / unsupported 等)。
  Stream<BleStatus> get statusStream {
    if (!_isSupported) {
      return Stream<BleStatus>.value(BleStatus.unsupported);
    }
    return _ble!.statusStream;
  }

  /// 是否正在扫描。
  Stream<bool> get isScanning => _scanning.stream;

  /// 开始扫描 (15 秒后自动停止)。
  Future<void> startScan() async {
    if (!_isSupported) {
      throw StateError('当前平台不支持 BLE');
    }
    await stopScan();
    _seen.clear();
    _results.add(const <DiscoveredDevice>[]);
    _sub = _ble!
        .scanForDevices(
          withServices: const <Uuid>[],
          scanMode: ScanMode.balanced,
        )
        .listen(
          (device) {
            _seen[device.id] = device;
            _results.add(List<DiscoveredDevice>.unmodifiable(_seen.values));
          },
          onError: (Object _) => stopScan(),
        );
    _scanning.add(true);
    _timer = Timer(const Duration(seconds: 15), stopScan);
  }

  Future<void> stopScan() async {
    _timer?.cancel();
    _timer = null;
    await _sub?.cancel();
    _sub = null;
    _scanning.add(false);
  }

  void dispose() {
    _results.close();
    _scanning.close();
  }
}
