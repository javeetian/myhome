/// BLE GATT 常量：UUID 统一管理，禁止散落在业务代码中。
/// 对应 WORK_V2 §6.3。
class BleConstants {
  BleConstants._();

  /// 设备透传服务 UUID。
  static const String serviceUuid = '0000fff0-0000-1000-8000-00805f9b34fb';

  /// TX 特征：手机 → 设备 (Write)。
  static const String txUuid = '0000fff1-0000-1000-8000-00805f9b34fb';

  /// RX 特征：设备 → 手机 (Notify)。
  static const String notifyUuid = '0000fff4-0000-1000-8000-00805f9b34fb';

  ///
  /// 注意：常见透传模块 (如 HM-10 风格 0xFFE1) 读写同用一个特征，
  /// 此时 txUuid 与 rxUuid 相同属正常现象。
  static const String rxUuid = '0000fff1-0000-1000-8000-00805f9b34fb';

  /// UI 包特征 (读取设备端 UI 压缩包，Phase 10 使用)。
  static const String uiBundleCharUuid = '0000fff2-0000-1000-8000-00805f9b34fb';
}
