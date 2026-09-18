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
 *     // 主循环/定时器 (1ms~10ms) 里: myhome_tick();
 * }
 * ```
 */
#ifndef MYHOME_GLUE_H
#define MYHOME_GLUE_H

#include "system/includes.h"   /* Jieli SDK 基础类型 u8/u16/u32 */

/**
 * 初始化协议框架 (绑定发送/状态/时间回调)。
 * [mtu] 传实际协商 MTU (ATT)，不要假设 247；不确定时传 247。
 */
void myhome_init(u16 mtu);

/** BLE 写入数据入口 (由 custom_fff0_write_handler 调用)。 */
void myhome_ble_on_write(u8* buffer, u16 buffer_size);

/** 周期调用 (主循环/定时器)：分片超时清理。 */
void myhome_tick(void);

/** BLE 断连时调用：清空帧缓冲与组装状态 (§21 会话不可复用)。 */
void myhome_on_disconnect(void);

/** 设备状态变化后调用：状态版本 +1 并推送 STATE 给手机。 */
void myhome_state_changed(void);

/** 主动推送事件 (name 与 device.yaml 的 events 对应)。 */
void myhome_send_event(const char* name, const char* data_json);

/** 诊断计数 (调试用)。 */
void myhome_dump_stats(void);

#endif /* MYHOME_GLUE_H */
