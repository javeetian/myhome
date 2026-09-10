import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @settings.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get settings;

  /// No description provided for @addDevice.
  ///
  /// In zh, this message translates to:
  /// **'添加设备'**
  String get addDevice;

  /// No description provided for @homeEmptyHint.
  ///
  /// In zh, this message translates to:
  /// **'还没有设备，点击上方按钮添加'**
  String get homeEmptyHint;

  /// No description provided for @removeDevice.
  ///
  /// In zh, this message translates to:
  /// **'移除'**
  String get removeDevice;

  /// 移除历史设备的确认文案
  ///
  /// In zh, this message translates to:
  /// **'确定从列表中移除「{name}」？'**
  String removeDeviceConfirm(String name);

  /// No description provided for @cancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get cancel;

  /// 历史设备卡片的最近连接时间
  ///
  /// In zh, this message translates to:
  /// **'上次连接：{time}'**
  String lastConnected(String time);

  /// No description provided for @unknownError.
  ///
  /// In zh, this message translates to:
  /// **'未知错误'**
  String get unknownError;

  /// No description provided for @sessionNotEstablished.
  ///
  /// In zh, this message translates to:
  /// **'设备会话未建立'**
  String get sessionNotEstablished;

  /// No description provided for @scanTitle.
  ///
  /// In zh, this message translates to:
  /// **'添加设备'**
  String get scanTitle;

  /// No description provided for @scanPermissionDenied.
  ///
  /// In zh, this message translates to:
  /// **'缺少蓝牙权限，请在系统设置中授权'**
  String get scanPermissionDenied;

  /// 开始扫描失败时的提示
  ///
  /// In zh, this message translates to:
  /// **'扫描失败: {error}'**
  String scanFailed(String error);

  /// 连接设备失败时的提示
  ///
  /// In zh, this message translates to:
  /// **'连接失败: {error}'**
  String connectFailed(String error);

  /// 演示设备启动失败时的提示
  ///
  /// In zh, this message translates to:
  /// **'演示启动失败: {error}'**
  String demoFailed(String error);

  /// No description provided for @stopScan.
  ///
  /// In zh, this message translates to:
  /// **'停止扫描'**
  String get stopScan;

  /// No description provided for @startScan.
  ///
  /// In zh, this message translates to:
  /// **'开始扫描'**
  String get startScan;

  /// No description provided for @demoCardTitle.
  ///
  /// In zh, this message translates to:
  /// **'Mock 设备演示'**
  String get demoCardTitle;

  /// No description provided for @demoCardSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'无需真实硬件，模拟完整交互链路'**
  String get demoCardSubtitle;

  /// 扫描结果数量标题
  ///
  /// In zh, this message translates to:
  /// **'扫描结果 ({count})'**
  String scanResultCount(int count);

  /// No description provided for @scanEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂未发现设备，点击右下角开始扫描'**
  String get scanEmpty;

  /// No description provided for @unknownDevice.
  ///
  /// In zh, this message translates to:
  /// **'未知设备'**
  String get unknownDevice;

  /// No description provided for @blePoweredOff.
  ///
  /// In zh, this message translates to:
  /// **'蓝牙未开启'**
  String get blePoweredOff;

  /// No description provided for @bleUnauthorized.
  ///
  /// In zh, this message translates to:
  /// **'蓝牙权限未授权，请在系统设置中开启'**
  String get bleUnauthorized;

  /// No description provided for @bleLocationDisabled.
  ///
  /// In zh, this message translates to:
  /// **'定位服务未开启'**
  String get bleLocationDisabled;

  /// No description provided for @bleUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'当前平台不支持 BLE'**
  String get bleUnsupported;

  /// No description provided for @developerMode.
  ///
  /// In zh, this message translates to:
  /// **'开发者模式'**
  String get developerMode;

  /// No description provided for @disconnectAndBack.
  ///
  /// In zh, this message translates to:
  /// **'断开并返回'**
  String get disconnectAndBack;

  /// No description provided for @uiServerNotStarted.
  ///
  /// In zh, this message translates to:
  /// **'UI 服务未启动'**
  String get uiServerNotStarted;

  /// UI Server 启动失败时抛出的错误
  ///
  /// In zh, this message translates to:
  /// **'UI Server 启动失败: {error}'**
  String uiServerStartFailed(String error);

  /// No description provided for @reconnecting.
  ///
  /// In zh, this message translates to:
  /// **'连接中断，正在重连…'**
  String get reconnecting;

  /// No description provided for @reconnected.
  ///
  /// In zh, this message translates to:
  /// **'已重新连接'**
  String get reconnected;

  /// 设备异常断开时的提示
  ///
  /// In zh, this message translates to:
  /// **'设备异常: {error}'**
  String deviceError(String error);

  /// No description provided for @deviceDisconnected.
  ///
  /// In zh, this message translates to:
  /// **'设备已断开'**
  String get deviceDisconnected;

  /// No description provided for @devPanelTitle.
  ///
  /// In zh, this message translates to:
  /// **'开发者模式 (§33)'**
  String get devPanelTitle;

  /// No description provided for @devDeviceId.
  ///
  /// In zh, this message translates to:
  /// **'设备 ID'**
  String get devDeviceId;

  /// No description provided for @devConnectionState.
  ///
  /// In zh, this message translates to:
  /// **'连接状态'**
  String get devConnectionState;

  /// No description provided for @devProtocolVersion.
  ///
  /// In zh, this message translates to:
  /// **'协议版本'**
  String get devProtocolVersion;

  /// No description provided for @devDeviceType.
  ///
  /// In zh, this message translates to:
  /// **'设备类型'**
  String get devDeviceType;

  /// No description provided for @devFirmwareVersion.
  ///
  /// In zh, this message translates to:
  /// **'固件版本'**
  String get devFirmwareVersion;

  /// No description provided for @devUiVersion.
  ///
  /// In zh, this message translates to:
  /// **'UI 版本'**
  String get devUiVersion;

  /// No description provided for @devCapabilities.
  ///
  /// In zh, this message translates to:
  /// **'能力'**
  String get devCapabilities;

  /// No description provided for @devTxBytes.
  ///
  /// In zh, this message translates to:
  /// **'TX 字节'**
  String get devTxBytes;

  /// No description provided for @devRxBytes.
  ///
  /// In zh, this message translates to:
  /// **'RX 字节'**
  String get devRxBytes;

  /// No description provided for @devRetries.
  ///
  /// In zh, this message translates to:
  /// **'重试次数'**
  String get devRetries;

  /// No description provided for @devCommandCount.
  ///
  /// In zh, this message translates to:
  /// **'命令数'**
  String get devCommandCount;

  /// No description provided for @devLatencyP50.
  ///
  /// In zh, this message translates to:
  /// **'命令延迟 P50'**
  String get devLatencyP50;

  /// No description provided for @devLatencyP95.
  ///
  /// In zh, this message translates to:
  /// **'命令延迟 P95'**
  String get devLatencyP95;

  /// No description provided for @devLatencyP99.
  ///
  /// In zh, this message translates to:
  /// **'命令延迟 P99'**
  String get devLatencyP99;

  /// No description provided for @devLastError.
  ///
  /// In zh, this message translates to:
  /// **'最近错误'**
  String get devLastError;

  /// No description provided for @phaseDisconnected.
  ///
  /// In zh, this message translates to:
  /// **'未连接'**
  String get phaseDisconnected;

  /// No description provided for @phaseScanning.
  ///
  /// In zh, this message translates to:
  /// **'扫描中'**
  String get phaseScanning;

  /// No description provided for @phaseConnecting.
  ///
  /// In zh, this message translates to:
  /// **'连接中'**
  String get phaseConnecting;

  /// No description provided for @phaseDiscovering.
  ///
  /// In zh, this message translates to:
  /// **'发现服务中'**
  String get phaseDiscovering;

  /// No description provided for @phaseNegotiating.
  ///
  /// In zh, this message translates to:
  /// **'协商中'**
  String get phaseNegotiating;

  /// No description provided for @phaseHandshaking.
  ///
  /// In zh, this message translates to:
  /// **'握手中'**
  String get phaseHandshaking;

  /// No description provided for @phaseLoadingUi.
  ///
  /// In zh, this message translates to:
  /// **'加载 UI 中'**
  String get phaseLoadingUi;

  /// No description provided for @phaseSyncingState.
  ///
  /// In zh, this message translates to:
  /// **'同步状态中'**
  String get phaseSyncingState;

  /// No description provided for @phaseConnected.
  ///
  /// In zh, this message translates to:
  /// **'已连接'**
  String get phaseConnected;

  /// No description provided for @phaseDisconnecting.
  ///
  /// In zh, this message translates to:
  /// **'断开中'**
  String get phaseDisconnecting;

  /// No description provided for @phaseReconnecting.
  ///
  /// In zh, this message translates to:
  /// **'重连中'**
  String get phaseReconnecting;

  /// No description provided for @phaseError.
  ///
  /// In zh, this message translates to:
  /// **'错误'**
  String get phaseError;

  /// No description provided for @language.
  ///
  /// In zh, this message translates to:
  /// **'语言'**
  String get language;

  /// No description provided for @followSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get followSystem;

  /// No description provided for @languageZh.
  ///
  /// In zh, this message translates to:
  /// **'简体中文'**
  String get languageZh;

  /// No description provided for @languageEn.
  ///
  /// In zh, this message translates to:
  /// **'English'**
  String get languageEn;

  /// No description provided for @theme.
  ///
  /// In zh, this message translates to:
  /// **'主题'**
  String get theme;

  /// No description provided for @themeLight.
  ///
  /// In zh, this message translates to:
  /// **'浅色主题'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In zh, this message translates to:
  /// **'深色主题'**
  String get themeDark;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
