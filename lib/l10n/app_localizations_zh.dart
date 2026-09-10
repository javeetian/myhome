// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get settings => '设置';

  @override
  String get addDevice => '添加设备';

  @override
  String get homeEmptyHint => '还没有设备，点击上方按钮添加';

  @override
  String get removeDevice => '移除';

  @override
  String removeDeviceConfirm(String name) {
    return '确定从列表中移除「$name」？';
  }

  @override
  String get cancel => '取消';

  @override
  String lastConnected(String time) {
    return '上次连接：$time';
  }

  @override
  String get unknownError => '未知错误';

  @override
  String get sessionNotEstablished => '设备会话未建立';

  @override
  String get scanTitle => '添加设备';

  @override
  String get scanPermissionDenied => '缺少蓝牙权限，请在系统设置中授权';

  @override
  String scanFailed(String error) {
    return '扫描失败: $error';
  }

  @override
  String connectFailed(String error) {
    return '连接失败: $error';
  }

  @override
  String demoFailed(String error) {
    return '演示启动失败: $error';
  }

  @override
  String get stopScan => '停止扫描';

  @override
  String get startScan => '开始扫描';

  @override
  String get demoCardTitle => 'Mock 设备演示';

  @override
  String get demoCardSubtitle => '无需真实硬件，模拟完整交互链路';

  @override
  String scanResultCount(int count) {
    return '扫描结果 ($count)';
  }

  @override
  String get scanEmpty => '暂未发现设备，点击右下角开始扫描';

  @override
  String get unknownDevice => '未知设备';

  @override
  String get blePoweredOff => '蓝牙未开启';

  @override
  String get bleUnauthorized => '蓝牙权限未授权，请在系统设置中开启';

  @override
  String get bleLocationDisabled => '定位服务未开启';

  @override
  String get bleUnsupported => '当前平台不支持 BLE';

  @override
  String get developerMode => '开发者模式';

  @override
  String get disconnectAndBack => '断开并返回';

  @override
  String get uiServerNotStarted => 'UI 服务未启动';

  @override
  String uiServerStartFailed(String error) {
    return 'UI Server 启动失败: $error';
  }

  @override
  String get reconnecting => '连接中断，正在重连…';

  @override
  String get reconnected => '已重新连接';

  @override
  String deviceError(String error) {
    return '设备异常: $error';
  }

  @override
  String get deviceDisconnected => '设备已断开';

  @override
  String get devPanelTitle => '开发者模式 (§33)';

  @override
  String get devDeviceId => '设备 ID';

  @override
  String get devConnectionState => '连接状态';

  @override
  String get devProtocolVersion => '协议版本';

  @override
  String get devDeviceType => '设备类型';

  @override
  String get devFirmwareVersion => '固件版本';

  @override
  String get devUiVersion => 'UI 版本';

  @override
  String get devCapabilities => '能力';

  @override
  String get devTxBytes => 'TX 字节';

  @override
  String get devRxBytes => 'RX 字节';

  @override
  String get devRetries => '重试次数';

  @override
  String get devCommandCount => '命令数';

  @override
  String get devLatencyP50 => '命令延迟 P50';

  @override
  String get devLatencyP95 => '命令延迟 P95';

  @override
  String get devLatencyP99 => '命令延迟 P99';

  @override
  String get devLastError => '最近错误';

  @override
  String get phaseDisconnected => '未连接';

  @override
  String get phaseScanning => '扫描中';

  @override
  String get phaseConnecting => '连接中';

  @override
  String get phaseDiscovering => '发现服务中';

  @override
  String get phaseNegotiating => '协商中';

  @override
  String get phaseHandshaking => '握手中';

  @override
  String get phaseLoadingUi => '加载 UI 中';

  @override
  String get phaseSyncingState => '同步状态中';

  @override
  String get phaseConnected => '已连接';

  @override
  String get phaseDisconnecting => '断开中';

  @override
  String get phaseReconnecting => '重连中';

  @override
  String get phaseError => '错误';

  @override
  String get language => '语言';

  @override
  String get followSystem => '跟随系统';

  @override
  String get languageZh => '简体中文';

  @override
  String get languageEn => 'English';

  @override
  String get theme => '主题';

  @override
  String get themeLight => '浅色主题';

  @override
  String get themeDark => '深色主题';
}
