import 'dart:async';

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
    this.connectTimeout = const Duration(seconds: 20),
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

  /// 实际协商结果 (WORK_V2 §6.4：不得假设 247)。
  int get mtu => _mtu;

  /// 当前连接状态。
  BleConnectionState get connectionState => _connectionState;

  bool get isConnected => _connectionState == BleConnectionState.connected;

  /// 连接状态流 (Phase 7 会话层消费)。
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
    } catch (_) {
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
    // 1. 连接并等待 connected (FRB 语义：取消订阅 = 断开，必须持有句柄)
    final connected = Completer<void>();
    _connSub = _peripheral.connect(deviceId).listen(
      (state) {
        _setState(state);
        if (state == BleConnectionState.connected && !connected.isCompleted) {
          connected.complete();
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
      onTimeout: () => throw TimeoutException('BLE 连接超时 ($deviceId)'),
    );

    // 2. MTU 协商，保存实际结果 (§6.4)
    _mtu = await _negotiateMtu();

    // 3. 发现服务并校验目标 GATT 特征存在
    await _peripheral.discoverServices(deviceId);
    final services = await _peripheral.serviceUuids(deviceId);
    if (!services.contains(BleConstants.serviceUuid)) {
      throw StateError('设备缺少目标服务 (${BleConstants.serviceUuid})');
    }
    final chars = await _peripheral.characteristicUuids(
      deviceId,
      BleConstants.serviceUuid,
    );
    if (!chars.contains(BleConstants.txUuid) ||
        !chars.contains(BleConstants.rxUuid)) {
      throw StateError(
        '设备缺少目标特征 (tx: ${BleConstants.txUuid}, rx: ${BleConstants.rxUuid})',
      );
    }

    // 4. 订阅 RX Notify
    _notifySub = _peripheral
        .subscribe(deviceId, BleConstants.serviceUuid, BleConstants.rxUuid)
        .listen(_notifications.add, onError: (Object e) {
      // Notify 订阅失败：状态标记断开并广播错误，不抛到 connect 调用方
      _setState(BleConnectionState.disconnected);
      _notifications.addError(e);
    });
  }

  Future<int> _negotiateMtu() async {
    try {
      return await _peripheral.requestMtu(_deviceId!, requestedMtu);
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
