/**
 * myhome 设备框架 · Jieli SDK 平台胶水
 *
 * 把协议运行时 (framework/core/runtime) 接到 Jieli SDK 的 BLE 通道：
 *   手机写入 FFF1 → custom_fff0_write_handler → myhome_ble_on_write()
 *   运行时 → myhome_send() → custom_fff0_notify → 手机 FFF3 通知
 *
 * 使用 (app 侧, 例如 apps/myhome/light1/device_app.c 或 app_main.c)：
 * ```c
 * void myhome_boot(void) {
 *     myhome_init(247);                 // 传实际协商 MTU (默认 247)
 *     // 分片超时清理由内部 10ms 软件定时器自动处理, 无需手动 tick
 * }
 * ```
 */
#ifndef MYHOME_GLUE_H
#define MYHOME_GLUE_H

#include "system/includes.h"   /* Jieli SDK 基础类型 u8/u16/u32 */

/* 告诉框架/生成的头文件：bool 已由 SDK 提供 (typedef unsigned char bool)，
 * 不要再引 <stdbool.h> (与 SDK 的 cpu.h 冲突)。必须在包含 device_api.h /
 * device_state.h / device_json.h 之前定义。 */
#define MYHOME_SDK_BOOL 1

/**
 * 初始化协议框架 (绑定发送/状态/时间回调)，并自动挂 10ms 软件定时器
 * (分片超时清理) —— app 无需再手动调 myhome_tick()。
 * [mtu] 传实际协商 MTU (ATT)，不要假设 247；不确定时传 247。
 */
void myhome_init(u16 mtu);

/** 停止框架定时器 (一般不用调；重启/低功耗场景可用)。 */
void myhome_deinit(void);

/** BLE 写入数据入口 (由 custom_fff0_write_handler 调用)。 */
void myhome_ble_on_write(u8* buffer, u16 buffer_size);

/**
 * 分片超时清理 (内部由 10ms 软件定时器自动调用)。
 * 如自行管理调度可调用 myhome_deinit() 后手动周期调本函数。
 */
void myhome_tick(void);

/** BLE 断连时调用：清空帧缓冲与组装状态 (§21 会话不可复用)。 */
void myhome_on_disconnect(void);

/** 设备状态变化后调用：状态版本 +1 并推送 STATE 给手机。 */
void myhome_state_changed(void);

/** 主动推送事件 (name 与 device.yaml 的 events 对应)。 */
void myhome_send_event(const char* name, const char* data_json);

/** 诊断计数 (调试用)。 */
void myhome_dump_stats(void);

/* ---------------- app 侧需提供的资源服务 (可选, §27) ----------------
 * 实现其一即可让 App 通过 RESOURCE_REQUEST 分块下载 ui.pkg：
 *   int myhome_resource_size(const char* path);                       // <0 = 不存在
 *   int myhome_resource_read(const char* path, u32 offset, u8* out, int cap);
 * 不实现时使用弱符号兜底 → 资源请求返回 5001 (其余功能不受影响)。
 */

#endif /* MYHOME_GLUE_H */
