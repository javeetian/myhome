# Device UI Platform — 快速上手

> 面向设备开发者：怎么跑 Studio、怎么设计 UI、怎么生成固件代码。
> 架构依据：[FRAMEWORK_V3.md](FRAMEWORK_V3.md) ｜ 流程依据：[WORK_V3.md](WORK_V3.md)
> 执行状态：[WORK_EXECUTE_V3.md](WORK_EXECUTE_V3.md)

---

# 1. 环境准备

```text
Flutter SDK (3.x，含 Windows 桌面支持)
Windows 10/11 + Visual Studio 2022+ (C++ 桌面开发，构建桌面应用与验证 C 代码)
(可选) Edge WebView2 Runtime — Win10/11 自带
```

验证：

```bash
flutter doctor
flutter devices          # 出现 Windows (desktop) 即可
```

---

# 2. 跑 Device Studio（PC 开发中心）

## 2.1 启动

```bash
cd myhome
flutter run -d windows -t lib/studio/studio_main.dart
```

## 2.2 界面（三栏）

```text
┌──────────────┬──────────────────────────────┬────────────────┐
│ 设备          │  UI 预览 (WebView2)          │ Inspector      │
│ ● Smart Light│                              │ 设备信息/状态    │
│ ○ Demo Light │                              │ State JSON     │
│              ├──────────────────────────────┤ 命令按钮        │
│              │ Protocol Console             │ Fault Injection│
│              │ TX/RX 帧日志                  │ (丢包/延迟/…)   │
└──────────────┴──────────────────────────────┴────────────────┘
```

## 2.3 操作

1. 点左侧 **Smart Light** → 自动加载 `devices/smart_light/build/ui.pkg`（若已构建）
2. 中间 WebView 渲染设备 UI → 点按钮 → 右侧状态实时更新 → 底部看协议帧
3. **Inspector 发命令**：开灯 / 亮度 50% / 色温 5000K
4. **Fault Injection**：拖动丢包/延迟滑块 → 观察重试与恢复；「注入断开」模拟掉线
5. **重置/断开**：右上角按钮；Demo Light 是内置 UI 的演示设备

## 2.4 UI Hot Reload

Studio 运行时直接编辑 `devices/smart_light/ui/` 下的文件 → 保存后约 300ms
自动重打包 → WebView 自动刷新（改动可见，无需重启）。

---

# 3. 编译与发布

## 3.1 移动 App（Android / iOS）

```bash
flutter build apk --release        # Android APK → build/app/outputs/flutter-apk/
flutter build ios --release        # iOS (需 macOS + Xcode)
```

## 3.2 桌面 App（Windows / macOS）

```bash
flutter build windows --release    # Windows App (lib/main.dart)
flutter build macos --release      # macOS App (需 Mac 机器)
```

## 3.3 Device Studio（PC 开发工具）

```bash
flutter build windows --release -t lib/studio/studio_main.dart   # Windows Studio
flutter build macos --release -t lib/studio/studio_main.dart      # macOS Studio
```

## 3.4 发布要点

- 产物位置：`build/<平台>/x64/runner/Release/` —— **整个目录**即发布包
  （exe + data/ + 依赖 DLL），拷贝到目标机器双击 exe 运行
- 目标机要求：Windows 10/11（自带 Edge WebView2 Runtime）；
  移动端无需 WebView2（用系统 WebView）
- Studio 发布包建议随附 `devices/` 设备工作目录（见 §2.3 新建设备）；
  没有也能用"文件 → 打开设备目录"导入
- 开发期：`flutter run`（加 `-t` 选入口）；发布后：双击 exe 即可，
  不需要任何 Flutter 环境

---

# 4. 设计 UI


## 4.1 目录结构

```text
devices/<设备id>/ui/
├── manifest.json      # UI 包描述
├── index.html         # 入口页面
├── style.css          # (可选)
├── app.js             # (可选)
└── assets/            # (可选) 图片/字体等
```

## 4.2 manifest.json（V3 格式）

```json
{
  "package": "smart_light_ui",
  "version": "1.0.0",
  "device": { "type": "light", "model": "L100" },
  "protocol": { "version": 1 },
  "entry": "index.html",
  "api_version": 1
}
```

## 4.3 页面规则（重要）

1. **全部相对路径**：`fetch('api/command')`、`assets/icon.png` —— session token 由
   App 的 `/s/<token>/` 前缀自动携带，页面无需感知
2. **不要手写 fetch / WebSocket**：使用 App 自动注入的 `deviceApi`（零样板代码）

## 4.4 Device API（页面直接使用）

```javascript
// 命令（返回 Promise，resolve 为 {status, data, error}）
await deviceApi.command('light.set_brightness', { value: 80 });

// 状态：设备是唯一数据源，页面订阅而非自行维护
window.deviceState;              // 当前状态对象
window.deviceStateVersion;       // 状态版本（Gap 检测用）
deviceApi.onState(function(state) { render(state); });   // 订阅全量状态
deviceApi.getState();            // 主动拉取

// 事件与补丁
deviceApi.onEvent('light.state_changed', function(data) { ... });
deviceApi.onPatch(function(ops) { ... });   // 补丁自动应用到 deviceState
```

## 4.5 最小示例

```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0,
        maximum-scale=1.0, user-scalable=no">
  <title>Smart Light</title>
</head>
<body>
  <button onclick="deviceApi.command('light.set_power', { power: true })">开灯</button>
  <div id="brightness">--</div>
  <script>
    deviceApi.onState(function(state) {
      document.getElementById('brightness').textContent = state.brightness;
    });
  </script>
</body>
</html>
```

完整示例：`devices/smart_light/ui/index.html`（电源/亮度/色温/温度 + 事件日志）。

## 4.6 打包与校验

```bash
dart run tools/device_cli.dart ui build devices/smart_light/ui
# → devices/smart_light/build/ui.pkg

dart run tools/device_cli.dart ui validate devices/smart_light/build/ui.pkg
# → PASS / 明确错误 (缺 manifest、entry 不存在、协议版本不匹配、哈希不符…)
```

---

# 5. 设备定义（device.yaml）

UI 对应的设备能力由 `devices/<设备id>/device.yaml` 定义（唯一数据源）：

```yaml
device:
  id: smart_light
  name: Smart Light
  model: L100

protocol:
  version: 1

api:
  version: 1

state:                      # 状态字段（类型 + 边界）
  power:
    type: bool
  brightness:
    type: uint8
    min: 0
    max: 100

commands:                   # 命令（页面 deviceApi.command 的 cmd 名）
  - name: light.set_brightness
    params:
      value:
        type: uint8
        min: 0
        max: 100

events:
  - name: light.state_changed
```

支持类型：`bool / uint8 / uint16 / int32 / float / string`。

校验：

```bash
dart run tools/device_cli.dart validate devices/smart_light/device.yaml
```

---

# 6. 生成固件代码

## 6.1 生成

```bash
dart run tools/device_cli.dart generate devices/smart_light/device.yaml
```

产出 `devices/smart_light/generated/`：

```text
generated/
├── c/
│   ├── device_api.h         命令处理原型（你要实现的部分）
│   ├── device_commands.c    命令路由 + 参数解析校验（已生成，勿改）
│   └── device_state.h       状态结构体
├── dart/device_api.dart     强类型 API（App 侧可选使用）
├── simulator/virtual_device.dart  虚拟设备骨架（Studio 模拟用）
└── manifest.json            UI manifest
```

## 6.2 移植到设备 SDK（WORK_V3 §44/§48）

```text
1. 拷贝 sdk/device/core/ + sdk/device/hardware/ 到 <设备SDK>/   (协议运行时)
2. 拷贝 generated/c/* 到 <设备SDK>/app/generated/               (应用层)
3. 编写 <设备SDK>/app/device_app.c                              (开发者代码)
4. 拷贝 ui.pkg 到固件 SPIFFS
5. MCU 编译（main.c / BLE driver / RTOS / HAL 由设备 SDK 提供）
```

## 6.3 开发者要写的唯一代码（§45）

实现 `device_api.h` 声明的函数 + `g_hardware`（真实硬件驱动调用）：

```c
/* device_app.c — 示例见 devices/smart_light/device_app.c */
static void hw_set_brightness(uint8_t value) {
    pwm_set(value);                      // 真实 PWM 驱动
}

const hardware_adapter_t g_hardware = {
    .set_power = hw_set_power,
    .set_brightness = hw_set_brightness,
    .set_color_temperature = hw_set_color_temperature,
    .get_temperature = hw_get_temperature,
};

int light_set_brightness(uint8_t value, char* response_json, int response_len) {
    g_hardware.set_brightness(value);
    return snprintf(response_json, response_len,
                    "{\"status\":\"ok\",\"data\":{\"brightness\":%u}}", value);
}
```

生成代码负责：协议路由、参数解析与校验（类型错/越界 → 3001，未知命令 → 3002）、
状态结构体。**不生成**：main.c / BLE 驱动 / RTOS / HAL（§42，SDK 提供）。

## 6.4 一致性保证

C 协议实现与 Dart 模拟器**字节级一致**（golden 向量验证）：

```bash
# sdk/device/ 下（VS 开发者命令行）：
cl /nologo /W3 /O2 /utf-8 /Fetest_sdk.exe \
   test/test_c_sdk.c core/protocol/crc16.c \
   core/protocol/ble_frame.c core/codec/device_json.c
test_sdk.exe    # ALL PASS (11 项)
```

模拟器验证通过 = 固件行为正确（同一协议、同一状态模型，§4 核心原则）。

---

# 7. 完整开发流程（一页图）

```text
┌─ PC 开发 (无需硬件) ──────────────────────────────────────┐
│ ① 定义设备    edit devices/<id>/device.yaml                 │
│ ② 校验        device validate devices/<id>/device.yaml      │
│ ③ 设计 UI     edit devices/<id>/ui/ (deviceApi 零样板)      │
│ ④ 打包        device ui build devices/<id>/ui               │
│ ⑤ 模拟验证    flutter run -d windows -t lib/studio/studio_main.dart
│              (点设备 → UI 交互 → 协议 Console → 故障注入 → Hot Reload)
└────────────────────────────────────────────────────────────┘
                    ↓ 开发完成
┌─ 设备移植 ────────────────────────────────────────────────┐
│ ⑥ 生成代码    device generate devices/<id>/device.yaml      │
│ ⑦ 拷贝        generated/c/ + sdk/device/* → 设备 SDK        │
│ ⑧ 写硬件      device_app.c (g_hardware + 命令处理)          │
│ ⑨ 编译烧录    MCU 编译 + ui.pkg 烧入 SPIFFS                 │
└────────────────────────────────────────────────────────────┘
```

---

# 8. 常见问题

| 问题 | 处理 |
|---|---|
| Studio 中间 WebView 空白 | 检查设备卡片是否已点启动；Protocol Console 是否有日志 |
| 修改 UI 后 Studio 没反应 | 确认有 `build/ui.pkg` 且 Studio 是 Smart Light 设备（自带 watch） |
| validate 报 unsupported type | 类型只支持 bool/uint8/uint16/int32/float/string |
| ui validate 报 Hash mismatch | manifest 声明的 hash 与包内容不符——重新 ui build |
| 命令返回 3001 | 参数类型/范围不符（对照 device.yaml 的 params 定义） |
| 命令返回 3002 | 设备侧命令路由未注册——重新 generate 并同步 generated/c |
| 断线后 Studio 卡住 | 点右上角「断开」→ 重新启动设备；App 侧有自动重连 |
