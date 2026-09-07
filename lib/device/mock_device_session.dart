import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'device_session.dart';

/// Mock 设备会话：无需真实硬件即可演示完整链路
/// (WebView → UI Server → 会话 → 响应/推送)。
class MockDeviceSession implements DeviceSession {
  MockDeviceSession({this.name = 'Mock 设备'});

  @override
  final String name;

  final StreamController<Map<String, dynamic>> _pushController =
      StreamController<Map<String, dynamic>>.broadcast();

  final Random _random = Random();
  Timer? _timer;
  bool _connected = false;
  bool _ledOn = false;
  double _temperature = 25.0;

  @override
  bool get isConnected => _connected;

  @override
  Future<void> init() async {
    _connected = true;
    // 模拟设备每 5 秒主动推送一次温度
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      _temperature += _random.nextDouble() * 0.6 - 0.3;
      _pushController.add(<String, dynamic>{
        'type': 'push',
        'data': <String, dynamic>{
          'temperature': double.parse(_temperature.toStringAsFixed(1)),
        },
      });
    });
  }

  @override
  Future<Map<String, dynamic>> sendCommand(
    Map<String, dynamic> command, {
    bool sync = true,
  }) async {
    // 模拟 BLE 往返延迟
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final id = command['id'];
    final cmd = command['cmd'] as String? ?? '';
    final data = <String, dynamic>{};
    switch (cmd) {
      case 'led_on':
        _ledOn = true;
        data['led'] = true;
      case 'led_off':
        _ledOn = false;
        data['led'] = false;
      case 'ping':
        data['pong'] = true;
      default:
        data['echo'] = command['params'];
    }
    _pushController.add(<String, dynamic>{
      'type': 'push',
      'data': <String, dynamic>{'led': _ledOn},
    });
    return <String, dynamic>{
      'type': 'response',
      'status': 'ok',
      'data': data,
      'id': id,
    };
  }

  @override
  Future<Uint8List> readUiBundle() async {
    return Uint8List.fromList(
      GZipEncoder().encode(utf8.encode(mockUiHtml)),
    );
  }

  @override
  Stream<Map<String, dynamic>> get pushes => _pushController.stream;

  @override
  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    _connected = false;
    await _pushController.close();
  }
}

/// 内置的 Mock 设备 UI 页面 (演示用)。
const String mockUiHtml = r'''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
<title>Mock 设备</title>
<style>
  body { font-family: -apple-system, sans-serif; margin: 0; background: #f5f6fa; overscroll-behavior: none; -webkit-touch-callout: none; }
  header { background: #3949ab; color: #fff; padding: 16px; text-align: center; font-size: 18px; }
  main { padding: 16px; max-width: 480px; margin: 0 auto; }
  button { display: block; width: 100%; padding: 14px; margin: 10px 0; border: none; border-radius: 8px; background: #3949ab; color: #fff; font-size: 16px; }
  button:active { opacity: 0.7; }
  .card { background: #fff; border-radius: 8px; padding: 12px; margin: 10px 0; box-shadow: 0 1px 3px rgba(0,0,0,0.12); }
  .temp { font-size: 32px; font-weight: bold; color: #3949ab; }
  #log { font-size: 12px; color: #666; font-family: monospace; white-space: pre-wrap; max-height: 160px; overflow: auto; }
  .led { display: inline-block; width: 10px; height: 10px; border-radius: 50%; background: #ccc; margin-right: 6px; }
  .led.on { background: #fdd835; }
</style>
</head>
<body>
<header>Mock 设备控制台</header>
<main>
  <div class="card">温度 <span class="temp" id="temp">--</span> ℃</div>
  <div class="card"><span class="led" id="led"></span>LED 状态：<span id="led-state">未知</span></div>
  <button onclick="sendCmd('led_on')">开灯</button>
  <button onclick="sendCmd('led_off')">关灯</button>
  <button onclick="sendCmd('ping')">Ping</button>
  <div class="card"><div id="log">事件日志：</div></div>
</main>
<script>
  var $ = function(id) { return document.getElementById(id); };
  function log(s) { $('log').textContent += '\n' + s; }

  // HTTP 指令：sync 模式，等待设备响应后更新 UI
  async function sendCmd(cmd) {
    log('→ ' + cmd);
    try {
      var r = await fetch('/api/command', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ cmd: cmd, params: {}, mode: 'sync', id: Date.now() })
      });
      var resp = await r.json();
      log('← ' + resp.status);
    } catch (e) {
      log('✗ ' + e);
    }
  }

  // WebSocket：接收设备主动推送
  var ws = new WebSocket('ws://localhost:8080/ws');
  ws.onmessage = function(e) {
    var m = JSON.parse(e.data);
    if (m.type === 'push' && m.data) {
      if (m.data.temperature !== undefined) { $('temp').textContent = m.data.temperature; }
      if (m.data.led !== undefined) {
        $('led').className = 'led' + (m.data.led ? ' on' : '');
        $('led-state').textContent = m.data.led ? '开' : '关';
      }
      log('push: ' + JSON.stringify(m.data));
    }
  };
  ws.onclose = function() { log('WS 断开'); };
</script>
</body>
</html>
''';
