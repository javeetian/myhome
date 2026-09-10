import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import 'ble_constants.dart';

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
  /// 只扫描广播 [BleConstants.serviceUuid] 的目标设备 (WORK_V2 §6.3)。
  Future<void> startScan() async {
    if (!_isSupported) {
      throw StateError('当前平台不支持 BLE');
    }
    await stopScan();
    _seen.clear();
    _results.add(const <DiscoveredDevice>[]);
    _sub = _ble!
        .scanForDevices(
          withServices: <Uuid>[Uuid.parse(BleConstants.serviceUuid)],
          scanMode: ScanMode.balanced,
        )
        .listen(
          (device) {
            // 系统层过滤之外再按广播内容过滤一次：部分平台 (如 Android)
            // 的 service 过滤依赖广播包，扫描响应命中的情况靠这里兜底。
            if (!BleScanner.matchesTarget(device)) {
              return;
            }
            _seen[device.id] = device;
            _results.add(List<DiscoveredDevice>.unmodifiable(_seen.values));
          },
          onError: (Object _) => stopScan(),
        );
    _scanning.add(true);
    _timer = Timer(const Duration(seconds: 15), stopScan);
  }

  /// 目标设备判定：广播/扫描响应中的服务 UUID 与 [BleConstants.serviceUuid]
  /// 匹配。兼容 16/32 位短 UUID 的广播形式 (按 BLE 规范零扩展到
  /// xxxxxxxx-0000-1000-8000-00805f9b34fb，0xFFE0 与
  /// 0000ffe0-0000-1000-8000-00805f9b34fb 等价)。
  static bool matchesTarget(DiscoveredDevice device) {
    final target = BleConstants.serviceUuid.replaceAll('-', '').toLowerCase();
    bool matches(Uuid uuid) {
      final hex = uuid.toString().replaceAll('-', '').toLowerCase();
      // 16/32 位短 UUID：零扩展为 32 位后拼接 BLE 基 UUID。
      final full = hex.length == 4 || hex.length == 8
          ? '${hex.padLeft(8, '0')}-0000-1000-8000-00805f9b34fb'
          : uuid.toString();
      return full.replaceAll('-', '').toLowerCase() == target;
    }

    return device.serviceUuids.any(matches) ||
        device.serviceData.keys.any(matches);
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
