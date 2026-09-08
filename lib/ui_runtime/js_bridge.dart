/// Device API Runtime (WORK_V2 §14.3/§14.5, Phase 9)：
/// 由 App 本地 UI Server 自动注入设备页面的 JS 运行时。
///
/// 提供：
///   `window.deviceState`    设备状态存储 (设备是唯一数据源, §21)
///   `window.deviceApi`      Promise 风格 Device API：
///     command(cmd, params)  → POST /api/command
///     getState()            → GET  /api/state
///     onState(fn)           → 订阅全量状态 (已有时立即回调)
///     onEvent(name, fn)     → 订阅设备事件
///     onPatch(fn)           → 订阅状态补丁 (自动应用到 deviceState)
///
/// 设备页面无需手写 fetch / WebSocket 样板代码。
const String deviceApiRuntimeJs = r'''
/**
 * Device UI Platform - Device API Runtime
 * 由 App 本地 UI Server 自动注入，请勿手动引入。
 */
(function () {
  if (window.__deviceApiRuntime) { return; }
  window.__deviceApiRuntime = true;

  var stateListeners = [];
  var patchListeners = [];
  var eventListeners = {};

  // ---- 状态 (§14.5)：设备是唯一数据源 ----
  function applyState(state) {
    window.deviceState = state;
    stateListeners.forEach(function (fn) { try { fn(state); } catch (e) { console.error(e); } });
    window.dispatchEvent(new CustomEvent('devicestate', { detail: state }));
  }

  // ---- Patch (JSON Patch 子集：replace / add / remove, §16.3) ----
  function applyPatch(ops) {
    var state = window.deviceState;
    (ops || []).forEach(function (op) {
      if (!op || !op.path) { return; }
      var parts = op.path.split('/').filter(function (s) { return s !== ''; });
      if (op.op === 'replace' || op.op === 'add') { setPath(state, parts, op.value); }
      else if (op.op === 'remove') { removePath(state, parts); }
    });
    patchListeners.forEach(function (fn) { try { fn(ops); } catch (e) { console.error(e); } });
    window.dispatchEvent(new CustomEvent('devicepatch', { detail: ops }));
  }

  function getParent(state, parts) {
    var cur = state;
    for (var i = 0; i < parts.length - 1; i++) { cur = cur[parts[i]]; }
    return cur;
  }
  function setPath(state, parts, value) {
    getParent(state, parts)[parts[parts.length - 1]] = value;
  }
  function removePath(state, parts) {
    delete getParent(state, parts)[parts[parts.length - 1]];
  }

  // ---- WebSocket (§14.4)：设备主动推送 ----
  var base = (location.pathname.match(/^\/s\/[^/]+\//) || ['/'])[0];
  var ws = new WebSocket(
    (location.protocol === 'https:' ? 'wss://' : 'ws://') + location.host + base + 'ws');
  ws.onmessage = function (e) {
    var m = JSON.parse(e.data);
    if (m.type === 'state') { applyState(m.state); }
    else if (m.type === 'patch') { applyPatch(m.ops); }
    else if (m.type === 'event') {
      (eventListeners[m.event] || []).forEach(function (fn) {
        try { fn(m.data); } catch (err) { console.error(err); }
      });
      window.dispatchEvent(new CustomEvent('deviceevent', { detail: m }));
    }
  };

  // ---- Device API (§14.3) ----
  window.deviceState = {};
  window.deviceApi = {
    /** POST /api/command → Promise<{status, data, error, request_id}> */
    command: function (cmd, params) {
      return fetch('api/command', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ cmd: cmd, params: params || {} })
      }).then(function (r) { return r.json(); });
    },
    /** GET /api/state → Promise<{version, state}> */
    getState: function () {
      return fetch('api/state').then(function (r) { return r.json(); });
    },
    /** 订阅全量状态；已有时立即回调 */
    onState: function (fn) {
      stateListeners.push(fn);
      if (window.deviceState && Object.keys(window.deviceState).length > 0) {
        fn(window.deviceState);
      }
    },
    /** 订阅事件：onEvent('temperature.changed', fn) */
    onEvent: function (name, fn) {
      (eventListeners[name] = eventListeners[name] || []).push(fn);
    },
    /** 订阅状态补丁 */
    onPatch: function (fn) { patchListeners.push(fn); }
  };
})();
''';

/// 把 Device API Runtime 的 `<script>` 标签注入 [html] 的 `<head>`。
/// 找不到 `<head>` 时注入到 `<html>` 之后；都没有则前置。
String injectDeviceApi(String html) {
  const tag = '<script src="__device_api.js"></script>';
  final lower = html.toLowerCase();
  final head = lower.indexOf('<head>');
  if (head >= 0) {
    return html.replaceRange(head + 6, head + 6, tag);
  }
  final htmlTag = lower.indexOf('<html');
  if (htmlTag >= 0) {
    final end = lower.indexOf('>', htmlTag);
    return html.replaceRange(end + 1, end + 1, tag);
  }
  return '$tag$html';
}
