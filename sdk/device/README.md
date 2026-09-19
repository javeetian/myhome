# Device SDK (C 参考实现)

真实设备（MCU）的协议运行时，与 Flutter 侧 Dart 实现**字节级一致**（golden 向量验证）。

`sdk/device/` 是**唯一源**：各 JieLi SDK 里的 `apps/myhome/framework/` 只是本目录的
部署产物（拷贝），改了这里必须重跑部署脚本，否则 SDK 编译的还是旧代码。

## 目录

```text
sdk/device/
├── core/
│   ├── protocol/    crc16 / ble_frame      帧编解码 (7B 头大端 + CRC16)
│   ├── codec/       device_json            JSON 参数提取 (生成代码依赖的契约函数)
│   └── runtime/     ★ 协议运行时           ble_stream_decoder 半包/粘包
│                                           fragment 分片器 + 组装器 (无动态内存)
│                                           device_runtime ACK/HELLO/PING/STATE/COMMAND 分发
├── hardware/        hardware_adapter.h     硬件接口 (函数指针结构体)
├── platform/jieli/  myhome_glue.h/.c       JieLi 平台胶水 (196 行, 换 IC 只改这一层)
├── examples/        device_app_example.c   设备应用示例
├── test/            test_c_sdk.c           一致性测试 (golden 向量, 与 Dart 逐字节比对)
│                    generated/             测试用桩 (device_info.h / device_api.h)
├── build_test.bat                          一致性测试构建 (Windows/MSVC)
└── deploy_to_sdk.ps1/.bat                  ★ 一键部署到目标 JieLi SDK
```

## 接入方式

固件侧只用 `platform/jieli/myhome_glue.h`（接口说明都在该头文件里）：

```c
myhome_init(247);                                   /* 传实际协商 MTU；内部自挂 10ms 定时器 */
custom_fff0_write_handler  -> myhome_ble_on_write(buffer, buffer_size);   /* BLE 写回调 */
HCI_EVENT_DISCONNECTION_COMPLETE -> myhome_on_disconnect();               /* 断连 */
```

要写**新平台的胶水**时，看 `core/runtime/device_runtime.h`：填三个回调
（`send` / `get_state_json` / `now_ms`），把 BLE 写入丢给 `device_runtime_on_bytes()`。

**运行时自动处理**（开发者不用管）：

| 手机发来 | 自动回 | 说明 |
|---|---|---|
| 任意消息 | ACK | App 侧 ReliableChannel 等 ACK，不发会重传直到失败 |
| HELLO / PING | HELLO_ACK / PONG | 设备信息来自生成的 device_info.h |
| STATE_REQUEST | STATE | 调 `get_state_json` 组包 |
| COMMAND | RESPONSE | 提取 cmd/params → `device_handle_command()` → 回填 request_id |
| RESOURCE_REQUEST | RESOURCE_RESPONSE | ui.pkg 等资源分块下载 |
| 重复帧（App 重发） | 重发 ACK | 不重复执行命令 |

调用链：

```text
device_runtime_on_bytes(bytes)
  → ble_stream_decoder (半包/粘包) → fragment_assembler (分片重组)
  → ACK + 按帧类型分发 → device_handle_command (参数校验) → device_app.c 硬件函数
  → RESPONSE 帧 → frag_sender 分片 → hooks.send → notify
```

容量配置（按芯片 RAM 调，在 `fragment.h` 顶部）：
`DEVICE_RX_MESSAGE_MAX` (1KB) / `DEVICE_RX_ASSEMBLY_SLOTS` (2) /
`DEVICE_TX_FRAME_MAX` (260) / `DEVICE_RUNTIME_JSON_MAX` (512)。

## 一致性契约

C 与 Dart 双实现必须字节级一致，否则模拟器验证无效：

| 项 | Dart | C | 验证 |
|---|---|---|---|
| CRC16 | lib/protocol/crc16.dart | core/protocol/crc16.c | 锚点 "123456789"→0x29B1 + 帧级 golden |
| Frame 布局 | lib/protocol/ble_frame.dart | core/protocol/ble_frame.h/.c | golden 逐字节比对 |
| 帧类型注册表 | FrameType (0x01-0x32) | FRAME_* 宏 | 同名常量 |
| 参数提取 | JsonCodec | device_json_get_* | 生成代码依赖契约 |
| Hardware Adapter | VirtualHardware (Dart) | hardware_adapter_t (C) | 字段一一对应 |

## 编译与测试

```bash
sdk/device/build_test.bat      # 需 VS2022+，输出 ALL PASS
```

golden 向量由 Dart 实现生成，改 Dart 协议后要重新生成并同步 C 测试。

## 部署与移植

```text
1. dart run tools/device_cli.dart generate devices/<id>/device.yaml
2. 设备目录 (device.yaml / ui / generated/ / device_app.c) 放进 <SDK>/apps/myhome/<设备>/
3. sdk\device\deploy_to_sdk.bat <SDK 根目录>     ← 全量重建 framework + 更新构建列表
4. ble_rcsp_server.c 接两行回调 (写回调 / 断连, 每个 SDK 一次)
5. apps\myhome\deploy_ui.bat 部署 ui.pkg + manifest.json
6. 在 SDK 根目录 make 编译
```

`deploy_to_sdk` 做的事（幂等，可反复跑）：重建 `<SDK>\apps\myhome\framework\`
（core/ hardware/ platform/，先删后拷，不留已删除的旧文件）、重写
`build\include_dir.txt` 的 `-I` 行、重写 `build\genFileList.c` 里标记块的源文件列表。
设备目录按 `device_app.c` 自动发现，不需要手工列举。

**换杰里 IC（jl380n → 别的 SDK）只需要动两处：**

| 要改的 | 说明 |
|---|---|
| `platform/<IC>/` 平台胶水 | 参考 platform/jieli/myhome_glue.c：写回调 → `myhome_ble_on_write()`、发送 → `notify`、断连 → `myhome_on_disconnect()`、分片超时定时器 |
| 设备目录的 `device_app.c` | 硬件驱动（PWM/GPIO/按键），实现 `device_api.h` + `g_hardware` |

`core/`（协议/编解码/运行时）与 `hardware/`（接口约定）与平台无关，一个字节都不用改。

## 开发者要写的代码

只有硬件操作：

```c
static void hw_set_brightness(uint8_t value) { pwm_set(value); }  // 真实驱动
const hardware_adapter_t g_hardware = { .set_brightness = hw_set_brightness, ... };
```

示例见 `examples/device_app_example.c`。
