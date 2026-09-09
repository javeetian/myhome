import 'dart:io';

import 'package:path/path.dart' as p;

import '../device/device_definition.dart';

/// 新建设备的默认文件模板 (内置，不依赖 devices/smart_light 目录存在)。
/// 模板内容与 Smart Light 参考设备一致 (WORK_V3 §2)。
class DeviceTemplates {
  DeviceTemplates._();

  /// 内置 Smart Light 设备定义 (VirtualLight / 演示设备共用)。
  /// 定义驱动：命令、状态、事件全部来自此 yaml，不写死在代码里。
  static DeviceDefinition builtInSmartLightDefinition() =>
      DeviceDefinition.fromYaml(
        deviceYaml('smart_light', 'Smart Light', 'L100'),
      );

  /// 新建设备目录：生成 device.yaml + ui/manifest.json + ui/index.html。
  static void createDeviceFiles({
    required String dirPath,
    required String id,
    required String name,
    required String model,
  }) {
    final dir = Directory(dirPath);
    final uiDir = Directory(p.join(dirPath, 'ui'));
    uiDir.createSync(recursive: true);
    File(p.join(dir.path, 'device.yaml'))
        .writeAsStringSync(deviceYaml(id, name, model));
    File(p.join(uiDir.path, 'manifest.json'))
        .writeAsStringSync(uiManifest(id, model));
    File(p.join(uiDir.path, 'index.html')).writeAsStringSync(uiIndexHtml(name));
  }

  /// Smart Light 完整设备定义 (状态/命令/事件齐全)。
  static String deviceYaml(String id, String name, String model) => '''
# $name
device:
  id: $id
  name: $name
  model: $model

protocol:
  version: 1

api:
  version: 1

state:
  power:
    type: bool

  brightness:
    type: uint8
    min: 0
    max: 100

  color_temperature:
    type: uint16
    min: 2700
    max: 6500

commands:
  - name: light.set_power
    params:
      power:
        type: bool

  - name: light.set_brightness
    params:
      value:
        type: uint8
        min: 0
        max: 100

  - name: light.set_color_temperature
    params:
      value:
        type: uint16
        min: 2700
        max: 6500

events:
  - name: $id.state_changed
''';

  /// V3 格式 UI manifest。
  static String uiManifest(String id, String model) => '''{
  "package": "${id}_ui",
  "version": "1.0.0",
  "device": {
    "type": "$id",
    "model": "$model"
  },
  "protocol": {
    "version": 1
  },
  "entry": "index.html",
  "api_version": 1
}
''';

  /// Smart Light UI 页面 (电源 / 亮度 / 色温 / 温度，deviceApi 零样板)。
  static String uiIndexHtml(String name) => r'''<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
<title>__NAME__</title>
<style>
  body { font-family: -apple-system, sans-serif; margin: 0; background: #f5f6fa; overscroll-behavior: none; -webkit-touch-callout: none; }
  header { background: #3949ab; color: #fff; padding: 16px; text-align: center; font-size: 18px; }
  main { padding: 16px; max-width: 480px; margin: 0 auto; }
  button { display: block; width: 100%; padding: 14px; margin: 10px 0; border: none; border-radius: 8px; background: #3949ab; color: #fff; font-size: 16px; }
  button:active { opacity: 0.7; }
  .card { background: #fff; border-radius: 8px; padding: 12px; margin: 10px 0; box-shadow: 0 1px 3px rgba(0,0,0,0.12); }
  .row { display: flex; justify-content: space-between; align-items: center; }
  .temp { font-size: 32px; font-weight: bold; color: #3949ab; }
  input[type=range] { width: 100%; }
  #log { font-size: 12px; color: #666; font-family: monospace; white-space: pre-wrap; max-height: 140px; overflow: auto; }
</style>
</head>
<body>
<header>__NAME__</header>
<main>
  <div class="card">温度 <span class="temp" id="temp">--</span> ℃</div>

  <div class="card row">
    <span>电源</span>
    <button style="width:auto;padding:8px 24px" id="power-btn" onclick="togglePower()">开</button>
  </div>

  <div class="card">亮度 <span id="br-value">--</span>%
    <input type="range" id="br" min="0" max="100" onchange="send('light.set_brightness', { value: +this.value })">
  </div>

  <div class="card">色温 <span id="ct-value">--</span>K
    <input type="range" id="ct" min="2700" max="6500" step="100" onchange="send('light.set_color_temperature', { value: +this.value })">
  </div>

  <div class="card"><div id="log">事件日志：</div></div>
</main>
<script>
  var $ = function(id) { return document.getElementById(id); };
  function log(s) { $('log').textContent += '\n' + s; }

  // Device API Runtime：由 App 自动注入，页面零样板代码
  deviceApi.onState(function(state) { applyState(state); });
  deviceApi.onEvent('light.state_changed', function(data) {
    log('state_changed v' + data.version);
  });

  async function send(cmd, params) {
    log('→ ' + cmd + (params ? ' ' + JSON.stringify(params) : ''));
    try {
      var resp = await deviceApi.command(cmd, params);
      log('← ' + resp.status + (resp.error ? ' ' + JSON.stringify(resp.error) : ''));
    } catch (e) { log('✗ ' + e); }
  }

  async function togglePower() {
    var current = window.deviceState.power !== undefined ? window.deviceState.power : false;
    await send('light.set_power', { power: !current });
  }

  function applyState(state) {
    if (state.temperature !== undefined) { $('temp').textContent = state.temperature; }
    if (state.power !== undefined) {
      $('power-btn').textContent = state.power ? '关' : '开';
    }
    if (state.brightness !== undefined) {
      $('br').value = state.brightness;
      $('br-value').textContent = state.brightness;
    }
    if (state.color_temperature !== undefined) {
      $('ct').value = state.color_temperature;
      $('ct-value').textContent = state.color_temperature;
    }
  }
</script>
</body>
</html>
'''.replaceAll('__NAME__', name);
}
