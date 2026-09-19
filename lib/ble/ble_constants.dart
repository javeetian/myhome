/// BLE GATT 常量：UUID 统一管理，禁止散落在业务代码中。
/// 对应 WORK_V2 §6.3。
class BleConstants {
  BleConstants._();

  /// 设备透传服务 UUID。
  static const String serviceUuid = '0000fff0-0000-1000-8000-00805f9b34fb';

  /// 手机 → 设备 (Write / WriteWithoutResponse)。
  static const String txUuid = '0000fff1-0000-1000-8000-00805f9b34fb';

  /// 设备 → 手机 (Notify)。
  ///
  /// 注意：固件 GATT 表里 FFF1 只可写，NOTIFY 挂在 FFF3
  /// (杰里 SDK: apps/common/third_party_profile/multi_protocol_main.c
  /// 的 rcsp_profile_data)，两者不是同一个特征。
  static const String notifyUuid = '0000fff3-0000-1000-8000-00805f9b34fb';

  /// 订阅用的 RX 特征，即 [notifyUuid]。
  static const String rxUuid = notifyUuid;

  /// FFF2 读特征 (读取设备端数据，如 UI 包，Phase 10 使用)。
  static const String uiBundleCharUuid = '0000fff2-0000-1000-8000-00805f9b34fb';

  /// 扫描时是否按 [serviceUuid] 过滤广播。
  ///
  /// 联调期置 false：杰里固件把 31 字节广播包全给了私有厂商数据
  /// (JL ID D6 05 + VID/PID + hash)，扫描响应里只有 flags + 设备名，
  /// 两边都不带 0xFFF0 —— 开着会一条都扫不到，任何 BLE 设备也进不来。
  /// 固件把 0xFFF0 加进扫描响应后改回 true。
  ///
  /// 与开关无关的安全网：连接后 reactive_ble_transport 会校验
  /// 0xFFF0 服务与 FFF1/FFF3 特征存在，扫到别的设备连接时会直接报错。
  static const bool filterScanByService = false;

  /// 扫描结果是否只保留有广播名的设备。
  ///
  /// 放开服务过滤后会扫到一堆无名设备 (手环/耳机/信标)，把列表淹掉，
  /// 所以默认只留有名字的。注意扫描响应里才带名字的设备第一次可能
  /// 是空名，它后续那条带名字的结果仍会进列表。
  static const bool requireDeviceName = true;
}
