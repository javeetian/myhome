// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get settings => 'Settings';

  @override
  String get addDevice => 'Add Device';

  @override
  String get homeEmptyHint =>
      'No devices yet — tap the button above to add one';

  @override
  String get removeDevice => 'Remove';

  @override
  String removeDeviceConfirm(String name) {
    return 'Remove \"$name\" from the list?';
  }

  @override
  String get cancel => 'Cancel';

  @override
  String lastConnected(String time) {
    return 'Last connected: $time';
  }

  @override
  String get unknownError => 'Unknown error';

  @override
  String get sessionNotEstablished => 'Device session not established';

  @override
  String get scanTitle => 'Add Device';

  @override
  String get scanPermissionDenied =>
      'Bluetooth permission missing. Please grant it in system settings.';

  @override
  String scanFailed(String error) {
    return 'Scan failed: $error';
  }

  @override
  String connectFailed(String error) {
    return 'Connection failed: $error';
  }

  @override
  String demoFailed(String error) {
    return 'Demo failed to start: $error';
  }

  @override
  String get stopScan => 'Stop Scan';

  @override
  String get startScan => 'Start Scan';

  @override
  String get demoCardTitle => 'Mock Device Demo';

  @override
  String get demoCardSubtitle =>
      'No real hardware required — simulate the full interaction chain';

  @override
  String scanResultCount(int count) {
    return 'Scan results ($count)';
  }

  @override
  String get scanEmpty =>
      'No devices found. Tap the button in the corner to start scanning.';

  @override
  String get unknownDevice => 'Unknown Device';

  @override
  String get blePoweredOff => 'Bluetooth is turned off';

  @override
  String get bleUnauthorized =>
      'Bluetooth permission denied. Please enable it in system settings.';

  @override
  String get bleLocationDisabled => 'Location services are disabled';

  @override
  String get bleUnsupported => 'BLE is not supported on this platform';

  @override
  String get developerMode => 'Developer Mode';

  @override
  String get disconnectAndBack => 'Disconnect and go back';

  @override
  String get uiServerNotStarted => 'UI server not started';

  @override
  String uiServerStartFailed(String error) {
    return 'UI server failed to start: $error';
  }

  @override
  String get reconnecting => 'Connection lost, reconnecting…';

  @override
  String get reconnected => 'Reconnected';

  @override
  String deviceError(String error) {
    return 'Device error: $error';
  }

  @override
  String get deviceDisconnected => 'Device disconnected';

  @override
  String get devPanelTitle => 'Developer Mode (§33)';

  @override
  String get devDeviceId => 'Device ID';

  @override
  String get devConnectionState => 'Connection State';

  @override
  String get devProtocolVersion => 'Protocol Version';

  @override
  String get devDeviceType => 'Device Type';

  @override
  String get devFirmwareVersion => 'Firmware Version';

  @override
  String get devUiVersion => 'UI Version';

  @override
  String get devCapabilities => 'Capabilities';

  @override
  String get devTxBytes => 'TX Bytes';

  @override
  String get devRxBytes => 'RX Bytes';

  @override
  String get devRetries => 'Retries';

  @override
  String get devCommandCount => 'Commands';

  @override
  String get devLatencyP50 => 'Command Latency P50';

  @override
  String get devLatencyP95 => 'Command Latency P95';

  @override
  String get devLatencyP99 => 'Command Latency P99';

  @override
  String get devLastError => 'Last Error';

  @override
  String get phaseDisconnected => 'Disconnected';

  @override
  String get phaseScanning => 'Scanning';

  @override
  String get phaseConnecting => 'Connecting';

  @override
  String get phaseDiscovering => 'Discovering';

  @override
  String get phaseNegotiating => 'Negotiating';

  @override
  String get phaseHandshaking => 'Handshaking';

  @override
  String get phaseLoadingUi => 'Loading UI';

  @override
  String get phaseSyncingState => 'Syncing State';

  @override
  String get phaseConnected => 'Connected';

  @override
  String get phaseDisconnecting => 'Disconnecting';

  @override
  String get phaseReconnecting => 'Reconnecting';

  @override
  String get phaseError => 'Error';

  @override
  String get language => 'Language';

  @override
  String get followSystem => 'Follow System';

  @override
  String get languageZh => '简体中文';

  @override
  String get languageEn => 'English';

  @override
  String get theme => 'Theme';

  @override
  String get themeLight => 'Light Theme';

  @override
  String get themeDark => 'Dark Theme';
}
