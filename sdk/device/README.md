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
│   └── codec/
│       └── device_json.h/.c    JSON 参数提取 (生成代码的 SDK 契约函数)
├── hardware/
│   └── hardware_adapter.h      Hardware Adapter (函数指针结构体, §27/§31)
└── test/
    └── test_c_sdk.c            一致性测试 (golden 向量, 与 Dart 逐字节比对)
```

> fragment / transport / platform 等其余目录按 §43 规划，随真实设备
> 移植需要逐模块补充；当前核心协议与契约已冻结。

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
