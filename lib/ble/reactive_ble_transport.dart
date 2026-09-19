import 'dart:async';

import '../core/app_log.dart';
import 'ble_constants.dart';
import 'ble_peripheral.dart';
import 'ble_transport.dart';

/// [BleTransport] 的 BLE 实现 (WORK_V2 §6)。
///
/// 连接流程 (WORK_V2 §6.4)：
///   Connect → Request MTU → 保存协商结果 → Discover GATT → 校验特征 → 订阅 RX
///
/// 通过 [BlePeripheral] 窄接口访问底层 Plugin，可注入 Fake 单测。
class ReactiveBleTransport implements BleTransport {
  ReactiveBleTransport({
    required BlePeripheral peripheral,
    this.requestedMtu = 247,
    this.connectTimeout = const Duration(seconds: 8),
  }) : _peripheral = peripheral;

  final BlePeripheral _peripheral;

  /// 连接后请求的 MTU (BLE 4.2 上限 247)。
  final int requestedMtu;

  /// 等待连接建立的超时时间。
  final Duration connectTimeout;

  /// MTU 协商失败时的保守回退值 (BLE 4.0 最小值)。
  static const int fallbackMtu = 23;

  final StreamController<List<int>> _notifications =
      StreamController<List<int>>.broadcast();

  final StreamController<BleConnectionState> _state =
      StreamController<BleConnectionState>.broadcast();

  StreamSubscription<BleConnectionState>? _connSub;
  StreamSubscription<List<int>>? _notifySub;

  String? _deviceId;
  int _mtu = fallbackMtu;
  BleConnectionState _connectionState = BleConnectionState.disconnected;

  /// 连接阶段日志：真机联调时输出到 logcat 的 flutter tag，
  /// 每一步都带耗时，卡在哪一步一眼能看出来。
  final AppLog _log = AppLog.instance;

  /// 实际协商结果 (WORK_V2 §6.4：不得假设 247)。
  int get mtu => _mtu;

  /// 当前连接状态。
  BleConnectionState get connectionState => _connectionState;

  bool get isConnected => _connectionState == BleConnectionState.connected;

  /// 连接状态流 (Phase 7 会话层消费)。
  @override
  Stream<BleConnectionState> get connectionStates => _state.stream;

  @override
  Stream<List<int>> get notifications => _notifications.stream;

  @override
  Future<void> connect(String deviceId) async {
    if (isConnected) {
      throw StateError('已连接 ($deviceId)，请先 disconnect');
    }
    _deviceId = deviceId;

    try {
      await _connectInternal(deviceId);
    } catch (e) {
      _log.error('BLE', '连接失败: $e', deviceId: deviceId);
      // 失败路径清理：不留半连接状态
      await _notifySub?.cancel();
      _notifySub = null;
      await _connSub?.cancel();
      _connSub = null;
      _setState(BleConnectionState.disconnected);
      rethrow;
    }
  }

  Future<void> _connectInternal(String deviceId) async {
    final sw = Stopwatch()..start();
    _log.info('BLE', '开始连接', deviceId: deviceId);

    // 1. 连接并等待 connected (FRB 语义：取消订阅 = 断开，必须持有句柄)
    //
    // 必须把 connectTimeout 透传给 FRB：Android 上"未指定超时"会把
    // connectGatt 的 autoConnect 置为 true —— 那是后台机会式连接，
    // GATT 操作在其上不可靠，表现为服务发现永远不完成 (onSearchComplete
    // 不回调)，最终连接被拆掉。传了超时 FRB 才会清掉该标志走直连。
    // 见 flutter_reactive_ble/lib/src/reactive_ble.dart connectToDevice 文档。
    final connected = Completer<void>();
    _connSub = _peripheral.connect(deviceId, timeout: connectTimeout).listen(
      (state) {
        _setState(state);
        if (connected.isCompleted) {
          return;
        }
        if (state == BleConnectionState.connected) {
          connected.complete();
        } else if (state == BleConnectionState.disconnected) {
          // 还没连上就收到 disconnected：链路已断/被设备拒绝，立刻失败。
          // Android 上这会先打 close() + unregisterApp()，以前我们要干等到
          // connectTimeout (8s) 才报超时 —— 白白多等好几秒。
          _log.warn('BLE', '连接建立前已断开，立即失败', deviceId: deviceId);
          connected.completeError(
            StateError('连接建立前已断开 ($deviceId)'),
          );
        }
      },
      onError: (Object e) {
        if (!connected.isCompleted) {
          connected.completeError(e);
        }
      },
    );
    await connected.future.timeout(
      connectTimeout,
      onTimeout: () => throw TimeoutException(
        'BLE 连接超时 ($deviceId, ${connectTimeout.inSeconds}s)',
      ),
    );
    _log.info('BLE', 'GATT 已连接 (${sw.elapsedMilliseconds}ms)',
        deviceId: deviceId);

    // 1.5 请求高优先级连接 (缩短连接间隔)：服务发现和之后每次往返都受连接间隔
    // 支配，实测 45ms→15ms 时发现耗时 860ms→65ms、单次往返 90ms→30ms。
    //
    // 这里不能 await：Android 侧该调用要等参数更新"完成"才返回。上游 FRB 把它
    // 硬编码成固定 2 秒空转，而且这 2 秒一直占着 RxAndroidBle 的每连接操作队列，
    // 会把紧随其后的服务发现压后 —— 所以我们 vendor 了一份补丁版
    // (third_party/reactive_ble_mobile，见其 PATCH.md) 把等待改成 1ms。
    unawaited(_requestHighPriority(deviceId));

    // 2. 先发现服务并校验特征，再协商 MTU。
    //
    // 顺序不能反：杰里固件在 MTU 交换收尾期间 (客户端收到第一个
    // onConfigureMTU 后设备还会再回一次最终值) 会丢掉紧随其后的
    // 服务发现请求 —— 实测表现为 SERVICE_DISCOVERY 超时、
    // onSearchComplete 永不回调。按默认 MTU(23) 先发现就没这个窗口；
    // MTU 只影响后续分片，不影响发现结果。
    await _peripheral.discoverServices(deviceId);
    _log.info('BLE', '服务发现完成 (${sw.elapsedMilliseconds}ms)',
        deviceId: deviceId);

    final services = await _peripheral.serviceUuids(deviceId);
    _log.info('BLE', '发现服务 [${services.join(' ')}]', deviceId: deviceId);
    if (!services.contains(BleConstants.serviceUuid)) {
      throw StateError('设备缺少目标服务 (${BleConstants.serviceUuid})');
    }
    final chars = await _peripheral.characteristicUuids(
      deviceId,
      BleConstants.serviceUuid,
    );
    _log.info('BLE', 'FFF0 下的特征 [${chars.join(' ')}]', deviceId: deviceId);
    if (!chars.contains(BleConstants.txUuid) ||
        !chars.contains(BleConstants.rxUuid)) {
      throw StateError(
        '设备缺少目标特征 (tx: ${BleConstants.txUuid}, rx: ${BleConstants.rxUuid})',
      );
    }

    // 3. MTU 协商，保存实际结果 (§6.4)
    _mtu = await _negotiateMtu();
    _log.info('BLE', 'MTU=$_mtu (${sw.elapsedMilliseconds}ms)',
        deviceId: deviceId);

    // 4. 订阅 RX Notify
    _notifySub = _peripheral
        .subscribe(deviceId, BleConstants.serviceUuid, BleConstants.rxUuid)
        .listen(_notifications.add, onError: (Object e) {
      // Notify 订阅失败：状态标记断开并广播错误，不抛到 connect 调用方
      _log.error('BLE', 'Notify 订阅失败: $e', deviceId: deviceId);
      _setState(BleConnectionState.disconnected);
      _notifications.addError(e);
    });
    _log.info('BLE', '已订阅 ${BleConstants.rxUuid} (${sw.elapsedMilliseconds}ms)',
        deviceId: deviceId);
  }

  /// 请求高优先级连接 (短连接间隔)。平台/设备不支持时忽略失败 ——
  /// 这只是提速手段，不影响功能。
  Future<void> _requestHighPriority(String deviceId) async {
    if (_peripheral is! ConnectionPriorityControl) {
      return;
    }
    // ConnectionPriorityControl 与 BlePeripheral 无继承关系，需显式转换
    final ctrl = _peripheral as ConnectionPriorityControl;
    try {
      await ctrl.requestConnectionPriority(deviceId, high: true);
      _log.info('BLE', '已请求高优先级连接 (缩短连接间隔)', deviceId: deviceId);
    } catch (e) {
      _log.warn('BLE', '连接优先级请求失败 (忽略): $e', deviceId: deviceId);
    }
  }

  Future<int> _negotiateMtu() async {
    try {
      final negotiated = await _peripheral.requestMtu(_deviceId!, requestedMtu);
      // 设备可能回一个比请求更大的值 (杰里固件回 517)：ATT 协商结果应为
      // 双方最小值，超出请求值的部分不作数 (平台也可能只上报第一个回调)。
      return negotiated > requestedMtu ? requestedMtu : negotiated;
    } catch (_) {
      // 部分平台/设备拒绝 MTU 请求，回退到保守值
      return fallbackMtu;
    }
  }

  void _setState(BleConnectionState state) {
    if (_connectionState == state) {
      return;
    }
    _connectionState = state;
    if (!_state.isClosed) {
      _state.add(state);
    }
  }

  @override
  Future<int> requestMtu(int mtu) async {
    if (!isConnected) {
      throw StateError('未连接，无法协商 MTU');
    }
    _mtu = await _negotiateMtu();
    return _mtu;
  }

  @override
  Future<void> write(List<int> data) async {
    if (!isConnected) {
      throw StateError('未连接，无法写入');
    }
    await _peripheral.write(
      _deviceId!,
      BleConstants.serviceUuid,
      BleConstants.txUuid,
      data,
    );
  }

  /// ACK 等小帧用无回执写：省掉每次 GATT 写响应的往返。
  @override
  Future<void> writeWithoutResponse(List<int> data) async {
    if (!isConnected) {
      throw StateError('未连接，无法写入');
    }
    await _peripheral.writeWithoutResponse(
      _deviceId!,
      BleConstants.serviceUuid,
      BleConstants.txUuid,
      data,
    );
  }

  @override
  Future<void> disconnect() async {
    await _notifySub?.cancel();
    _notifySub = null;
    await _connSub?.cancel(); // FRB 语义：取消连接流订阅 = 断开 BLE
    _connSub = null;
    _setState(BleConnectionState.disconnected);
  }

  /// 释放全部底层资源。
  Future<void> dispose() async {
    await disconnect();
    await _state.close();
    await _notifications.close();
  }
}
