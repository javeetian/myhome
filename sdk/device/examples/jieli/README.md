# apps/myhome · 设备 UI 平台固件侧

本目录是 Device Studio 生成代码在 **Jieli SDK** 里的运行目录。
一个设备 = 一个子目录；公共部分在 `framework/`。

```text
apps/myhome/
├── framework/                     ← 公共部分 (所有设备共用)
│   ├── core/
│   │   ├── protocol/              crc16 / ble_frame (帧编解码)
│   │   ├── codec/                 device_json (参数提取, 生成代码契约)
│   │   └── runtime/               协议运行时 ★
│   │       ├── ble_stream_decoder  字节流 → 帧 (半包/粘包)
│   │       ├── fragment            分片器 + 组装器 (无动态内存)
│   │       └── device_runtime      ACK / HELLO / PING / STATE / COMMAND / RESOURCE
│   ├── hardware/
│   │   └── hardware_adapter.h     硬件抽象 (与 Dart VirtualHardware 对应)
│   ├── myhome_glue.h/.c           Jieli 平台胶水 (send / 状态 / tick)
│   └── README.md                  本文件
│
└── light1/                        ← 设备: light1 (Studio 生成的设备目录)
    ├── device.yaml                设备定义 (唯一数据源)
    ├── ui/                        设备 UI 源码
    ├── build/ui.pkg               UI 包 (烧入 SPIFFS / 或运行时下发)
    ├── generated/                 Studio 生成 (★ 重新生成会覆盖)
    │   ├── c/device_api.h/.c      命令原型 + 参数校验路由
    │   ├── c/device_state.h       状态结构体
    │   ├── c/device_info.h        设备元信息 (HELLO_ACK 用)
    │   ├── c/device_commands.c    命令表
    │   ├── dart/ · simulator/ · manifest.json
    └── device_app.c               ★ 开发者代码 (唯一的硬件实现处)
```

## 数据流

```text
手机 App (Device Studio / 手机端)
   │ BLE 写入 FFF1
   ▼
ble_rcsp_server.c: custom_fff0_write_handler()
   │ myhome_ble_on_write()
   ▼
framework/core/runtime
   ├── 帧解码 (半包/粘包) → 分片重组
   ├── 回 ACK (§9.1 App 依赖)
   ├── HELLO → HELLO_ACK    PING → PONG    STATE_REQUEST → STATE
   └── COMMAND → device_handle_command()  ← generated/c/device_api.c
                     ↓
              device_app.c 硬件函数 (你写的)
                     ↓
              RESPONSE 帧 → 分片 → myhome_send()
                     ▼
        custom_fff0_notify() → 手机 FFF3 通知
```

## 编译配置 (已改好)

| 文件 | 改动 |
|---|---|
| `build/include_dir.txt` | 追加 `-Iapps/myhome/framework`、`-Iapps/myhome/framework/core/runtime`、`-Iapps/myhome/light1/generated/c` |
| `build/Makefile.mk` | 追加 `c_SRC_FILES +=` myhome 的 10 个 .c (framework 6 + 胶水 + device_app + 生成 2) |
| `ble_rcsp_server.c` | `custom_fff0_write_handler` 改为调 `myhome_ble_on_write`；断连事件里调 `myhome_on_disconnect()` |

## 设备侧要做的两件事

**1. 初始化 (app_main.c 或 BLE 初始化后)**

```c
#include "myhome_glue.h"
extern void light1_app_init(void);

// 启动时：
light1_app_init();          // 内部调 myhome_init(247) + 同步硬件初值
```

**2. 周期 tick (主循环 / 定时器，1~10ms)**

```c
myhome_tick();              // 分片组装超时清理
```
> 兜底：忘记调 `myhome_init` 时，第一条 BLE 数据到达会自动初始化；
> 但不调 `myhome_tick` 会导致不完整分片的消息无法超时清理（占槽位）。

## 新增设备 (例如 light2)

```bash
# 1. Studio 里「新建设备」或直接建目录
apps/myhome/light2/{device.yaml, ui/, generated/}

# 2. 生成代码
dart run tools/device_cli.dart generate apps/myhome/light2/device.yaml

# 3. 写 device_app.c (照抄 light1 改命令实现)
# 4. 构建配置追加两行 (include 路径 + 源文件)
#    -Iapps/myhome/light2/generated/c
#    c_SRC_FILES += apps/myhome/light2/device_app.c \
#                   apps/myhome/light2/generated/c/device_api.c \
#                   apps/myhome/light2/generated/c/device_commands.c
```

## 常见问题

| 现象 | 排查 |
|---|---|
| 手机连上但命令无响应 | 看串口日志 ACK 是否发出；确认 `myhome_ble_on_write` 被调用 |
| App 一直重试 | ACK 没发出 → 检查 notify 是否成功 (手机需先使能 FFF3 通知) |
| 握手失败 | `generated/c/device_info.h` 是否生成、是否在 include 路径 |
| 状态不更新 | `device_app.c` 里改状态后是否调了 `myhome_state_changed()` |
| 命令返回 3001 | 参数类型/范围不符 → 对照 device.yaml 的 params 定义 |
