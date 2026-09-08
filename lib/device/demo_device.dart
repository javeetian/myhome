import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../protocol/protocol_messages.dart';
import '../ui_runtime/ui_package.dart';
import 'protocol_device.dart';

/// 演示设备 (WORK_V2 §30 硬件到位前的替代)：
/// 走完整协议栈的脚本设备，App 侧全程真实代码路径。
/// Phase 6-9 起基于 [ProtocolDevice] 基类 (共享协议行为, WORK_V3 §4)，
/// 只保留演示业务行为。
///
/// 命令：led_on / led_off / set_brightness / ping；
/// 连接后推初始 STATE；每 5 秒温度推送；LED 变化发 led.changed 事件。
class DemoDevice extends ProtocolDevice {
  DemoDevice({this.deviceId = 'demo-light', this.name = 'Demo Light'});

  @override
  final String deviceId;

  @override
  final String name;

  @override
  String get uiVersion => _uiVersion;

  static const String _uiVersion = '1.0.0';

  final Random _random = Random();
  int _stateVersion = 0;
  bool _led = false;
  int _brightness = 80;
  double _temperature = 25.0;
  Timer? _timer;

  Uint8List? _pkgCache;

  @override
  DeviceHelloAck helloAckFor(DeviceHello hello) => DeviceHelloAck(
        requestId: hello.requestId,
        protocolVersion: 1,
        deviceType: 'light',
        deviceModel: 'demo-1',
        firmwareVersion: '1.0.0',
        uiVersion: _uiVersion,
        capabilities: const <String>['power', 'brightness', 'led', 'temperature'],
      );

  @override
  Future<void> onDeviceConnect() async {
    _stateVersion = 1;
    pushState(currentState);
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      _temperature += _random.nextDouble() * 0.6 - 0.3;
      pushState(_nextSnapshot());
    });
  }

  @override
  Future<void> onDeviceDisconnect() async {
    _timer?.cancel();
    _timer = null;
  }

  @override
  DeviceState get currentState =>
      DeviceState(version: _stateVersion, state: _state);

  DeviceState _nextSnapshot() =>
      DeviceState(version: ++_stateVersion, state: _state);

  Map<String, dynamic> get _state => <String, dynamic>{
        'led': _led,
        'brightness': _brightness,
        'temperature': double.parse(_temperature.toStringAsFixed(1)),
      };

  @override
  Future<DeviceResponse?> handleCommand(DeviceCommand command) async {
    final data = <String, dynamic>{};
    switch (command.cmd) {
      case 'led_on':
        _led = true;
        data['led'] = true;
      case 'led_off':
        _led = false;
        data['led'] = false;
      case 'set_brightness':
        final value = command.params['value'];
        if (value is num) {
          _brightness = value.toInt().clamp(0, 100);
        }
        data['brightness'] = _brightness;
      case 'ping':
        data['pong'] = true;
      default:
        data['echo'] = command.params;
    }
    final snapshot = _nextSnapshot();
    pushState(snapshot);
    if (command.cmd == 'led_on' || command.cmd == 'led_off') {
      sendEvent('led.changed', <String, dynamic>{'led': _led});
    }
    return DeviceResponse(requestId: command.requestId, data: data);
  }

  @override
  Uint8List? resourceBytes(String path) {
    switch (path) {
      case 'manifest.json':
        return Uint8List.fromList(utf8.encode(_manifestJson));
      case 'ui.pkg':
        return _uiPkg;
      default:
        return null;
    }
  }

  /// ui.pkg 字节 (§15.2)：manifest.json + index.html + assets/。
  Uint8List get _uiPkg => _pkgCache ??= UiPackage.pack(<String, Uint8List>{
        'manifest.json': Uint8List.fromList(utf8.encode(_manifestJson)),
        'index.html': Uint8List.fromList(utf8.encode(demoUiHtml)),
        'assets/icon.svg': Uint8List.fromList(utf8.encode(_iconSvg)),
      });

  String get _manifestJson => jsonEncode(<String, dynamic>{
        'protocol': 1,
        'ui_version': _uiVersion,
        'device': <String, dynamic>{'type': 'light', 'model': 'demo-1'},
        'entry': 'index.html',
        'capabilities': <String>['power', 'brightness', 'led', 'temperature'],
      });
}

/// 演示设备图标 (ui.pkg assets 示例文件)。
const String _iconSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32">
  <circle cx="16" cy="16" r="14" fill="#3949ab"/>
  <circle cx="16" cy="16" r="7" fill="#fdd835"/>
</svg>
''';

/// 演示设备 UI 页面。
///
/// 约定 (与 Phase 10 UI 规范一致)：
///   全部使用相对路径 —— 由服务端 `/s/<token>/` 前缀自动携带 session token (§13.5)；
///   WebSocket 地址从 location 推导，无需感知 token 值。
const String demoUiHtml = r'''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
<title>Demo Light</title>
<style>
  body { font-family: -apple-system, sans-serif; margin: 0; background: #f5f6fa; overscroll-behavior: none; -webkit-touch-callout: none; }
  header { background: #3949ab; color: #fff; padding: 16px; text-align: center; font-size: 18px; }
  main { padding: 16px; max-width: 480px; margin: 0 auto; }
  button { display: block; width: 100%; padding: 14px; margin: 10px 0; border: none; border-radius: 8px; background: #3949ab; color: #fff; font-size: 16px; }
  button:active { opacity: 0.7; }
  .card { background: #fff; border-radius: 8px; padding: 12px; margin: 10px 0; box-shadow: 0 1px 3px rgba(0,0,0,0.12); }
  .temp { font-size: 32px; font-weight: bold; color: #3949ab; }
  input[type=range] { width: 100%; }
  #log { font-size: 12px; color: #666; font-family: monospace; white-space: pre-wrap; max-height: 160px; overflow: auto; }
  .led { display: inline-block; width: 10px; height: 10px; border-radius: 50%; background: #ccc; margin-right: 6px; }
  .led.on { background: #fdd835; }
</style>
</head>
<body>
<header>Demo Light</header>
<main>
  <div class="card">温度 <span class="temp" id="temp">--</span> ℃</div>
  <div class="card"><span class="led" id="led"></span>LED：<span id="led-state">--</span></div>
  <button onclick="send('led_on')">开灯</button>
  <button onclick="send('led_off')">关灯</button>
  <div class="card">亮度 <span id="br-value">80</span>%
    <input type="range" id="br" min="0" max="100" value="80" onchange="send('set_brightness', { value: +this.value })">
  </div>
  <button onclick="send('ping')">Ping</button>
  <div class="card"><div id="log">事件日志：</div></div>
</main>
<script>
  var $ = function(id) { return document.getElementById(id); };
  function log(s) { $('log').textContent += '\n' + s; }

  // Device API Runtime (Phase 9)：由 App 自动注入，页面零样板代码
  deviceApi.onState(function(state) {
    applyState(state);
    log('state v' + (window.__stateVersion || '?') + ': ' + JSON.stringify(state));
  });
  deviceApi.onEvent('led.changed', function(data) {
    log('event led.changed: ' + JSON.stringify(data));
  });

  async function send(cmd, params) {
    log('→ ' + cmd + (params ? ' ' + JSON.stringify(params) : ''));
    try {
      var resp = await deviceApi.command(cmd, params);
      log('← ' + resp.status + (resp.error ? ' ' + JSON.stringify(resp.error) : ''));
    } catch (e) { log('✗ ' + e); }
  }

  function applyState(state) {
    if (state.temperature !== undefined) { $('temp').textContent = state.temperature; }
    if (state.led !== undefined) {
      $('led').className = 'led' + (state.led ? ' on' : '');
      $('led-state').textContent = state.led ? '开' : '关';
    }
    if (state.brightness !== undefined) {
      $('br').value = state.brightness;
      $('br-value').textContent = state.brightness;
    }
  }
</script>
</body>
</html>
''';
