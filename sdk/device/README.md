# Device SDK (C 参考实现)

WORK_V3 Phase 26-27。真实设备（MCU）的协议运行时参考实现，
与 Flutter 侧 Dart 实现**字节级一致**（golden 向量验证）。

## 目录 (WORK_V3 §43)

```text
sdk/device/
├── core/
│   ├── protocol/
│   │   ├── crc16.h/.c          CRC16/CCITT-FALSE (poly 0x1021, init 0xFFFF)
│   │   └── ble_frame.h/.c      Frame 编解码 (7B 头大端 + CRC16)
│   ├── codec/
│   │   └── device_json.h/.c    JSON 参数提取 (生成代码的 SDK 契约函数)
│   └── runtime/                ★ 协议运行时 (接入 BLE 只需这一个入口)
│       ├── ble_stream_decoder.h/.c  字节流 → 帧 (半包/粘包)
│       ├── fragment.h/.c            分片器 + 组装器 (无动态内存)
│       └── device_runtime.h/.c      ACK / HELLO / PING / STATE / COMMAND 分发
├── hardware/
│   └── hardware_adapter.h      Hardware Adapter (函数指针结构体, §27/§31)
├── build_test.bat              一致性测试构建 (Windows/MSVC)
└── test/
    ├── test_c_sdk.c            一致性测试 (golden 向量, 与 Dart 逐字节比对)
    └── generated/              测试用生成代码桩 (device_info.h / device_api.h)
```

## 接入固件：协议运行时 (推荐路径)

`device_runtime` 把「BLE 字节流 → 业务命令 → 响应」整条链路封装好，
固件侧只需要 **三个回调 + 一个入口**：

```c
/* 1. 平台发送：把字节写给手机 (复用现有 notify) */
static void my_send(const uint8_t* data, uint16_t len, void* ctx) {
    custom_fff0_notify(data, len);           /* Jieli SDK: FFF3 通知 */
}

/* 2. 上报状态：返回当前状态 JSON (字段与 device.yaml 的 state 一致) */
static int my_state_json(char* out, int cap, void* ctx) {
    return snprintf(out, cap, "{\"power\":%s,\"brightness\":%u}",
                    g_power ? "true" : "false", g_brightness);
}

/* 3. 时间源 (分片超时用，可 NULL) */
static uint32_t my_now_ms(void) { return jiffies_msec(); }

static device_runtime_t g_rt;

void myhome_init(void) {
    device_runtime_hooks_t hooks = {
        .send = my_send,
        .get_state_json = my_state_json,
        .now_ms = my_now_ms,
    };
    device_runtime_init(&g_rt, &hooks, negotiated_mtu);   /* 传实际协商 MTU */
}

/* ★ 唯一接入点：BLE 写入回调 */
static void custom_fff0_write_handler(u8 *buffer, u16 buffer_size) {
    device_runtime_on_bytes(&g_rt, buffer, buffer_size);
}

/* 主循环/定时器里调用：分片超时清理 */
void myhome_tick(void) { device_runtime_tick(&g_rt, my_now_ms()); }

/* 状态变化后调用：版本 +1 并推送 STATE 给 App (§16) */
void myhome_state_changed(void) { device_runtime_notify_state_changed(&g_rt); }

/* 主动事件 (§10.4) */
void myhome_report_temperature(float t) {
    char data[32];
    snprintf(data, sizeof(data), "{\"value\":%.1f}", t);
    device_runtime_send_event(&g_rt, "temperature.changed", data);
}
```

**运行时自动处理**（开发者不用管）：

| 手机发来 | 固件自动回 | 说明 |
|---|---|---|
| 任意消息 | **ACK 帧** | App 侧 ReliableChannel 等 ACK，不发会重传直至失败 |
| HELLO | HELLO_ACK | 设备类型/型号/协议版本/能力列表 (来自生成的 device_info.h) |
| PING | PONG | 心跳 (App 失联判定) |
| STATE_REQUEST | STATE | 调 `get_state_json` 组包 |
| COMMAND | RESPONSE | 提取 cmd/params → `device_handle_command()` → 回填 request_id |
| RESOURCE_REQUEST | RESOURCE_RESPONSE | 调 `get_resource` (ui.pkg 等，未接时回 5001) |
| 重复帧 (App 重发) | 重发 ACK | 不重复执行命令 |

调用链：

```text
device_runtime_on_bytes(bytes)
  → ble_stream_decoder (半包/粘包)
  → fragment_assembler (分片重组)
  → send_ack + 按帧类型分发
  → device_handle_command (生成代码: 参数校验)
  → device_app.c 的硬件函数 (开发者实现)
  → RESPONSE 帧 → frag_sender 分片 → hooks.send → notify
```

**容量配置** (按芯片 RAM 调整，在 `fragment.h` 顶部)：
`DEVICE_RX_MESSAGE_MAX` (默认 1KB) / `DEVICE_RX_ASSEMBLY_SLOTS` (2) /
`DEVICE_TX_FRAME_MAX` (260) / `DEVICE_RUNTIME_JSON_MAX` (512)。

## 一致性契约（最重要）

C 与 Dart 双实现必须保持字节级一致，否则模拟器验证无效 (§4 核心原则)：

| 项 | Dart | C | 验证 |
|---|---|---|---|
| CRC16 | lib/protocol/crc16.dart | core/protocol/crc16.c | 锚点 "123456789"→0x29B1 + 帧级 golden |
| Frame 布局 | lib/protocol/ble_frame.dart | core/protocol/ble_frame.h/.c | golden 逐字节比对 |
| 帧类型注册表 | FrameType (0x01-0x32) | FRAME_* 宏 | 同名常量 |
| 参数提取 | JsonCodec | device_json_get_* | 生成代码依赖契约 |
| Hardware Adapter | VirtualHardware (Dart) | hardware_adapter_t (C) | 字段一一对应 |

## 编译与测试（Windows）

```bash
# vcvars64 (VS2022+) 后：
cl /nologo /W3 /O2 /utf-8 /Fetest_sdk.exe \
   test/test_c_sdk.c core/protocol/crc16.c \
   core/protocol/ble_frame.c core/codec/device_json.c
test_sdk.exe   # ALL PASS (11 项)
```

golden 向量由 Dart 实现生成（`dart run` 临时脚本打印 FRAME hex），
更新 Dart 协议时需重新生成并同步 C 测试。

## 设备移植流程 (WORK_V3 §48/§54)

```text
1. dart run tools/device_cli.dart generate devices/<id>/device.yaml
2. 拷贝 generated/c/* 到 <设备SDK>/app/generated/
3. 拷贝本 SDK 的 core/ + hardware/ 到 <设备SDK>/
4. 开发者编写 device_app.c (实现 device_api.h 的函数 + g_hardware)
5. MCU 编译 (main.c / BLE driver / RTOS / HAL 由设备 SDK 提供, §42)
6. ui.pkg 烧入 SPIFFS
```

## 开发者要写的代码 (§45)

只有硬件操作：

```c
static void hw_set_brightness(uint8_t value) { pwm_set(value); }  // 真实驱动
const hardware_adapter_t g_hardware = { .set_brightness = hw_set_brightness, ... };
```

示例见 devices/smart_light/device_app.c。
