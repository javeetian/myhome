/**
 * light1 设备应用 (开发者代码, WORK_V3 §45)
 *
 * 你只需要写这个文件：实现 device_api.h 声明的命令函数 + 硬件操作。
 * 协议路由、参数校验、分片、ACK、握手全部由 framework/ 提供。
 *
 * 生成的接口 (generated/c/device_api.h)：
 *   int light_set_power(bool power, char* resp, int len);
 *   int light_set_brightness(uint8_t value, char* resp, int len);
 *   int light_set_color_temperature(uint16_t value, char* resp, int len);
 *
 * 返回值约定：
 *   返回 snprintf 写入长度 → 正常响应 (运行时自动补 request_id)
 *   返回 3001/3002        → 参数错误 / 未知命令 (运行时组错误响应)
 */
#include "device_api.h"
#include "device_state.h"
#include "device_info.h"
#include "jiffies.h"

#include "framework/myhome_glue.h"
#include "framework/hardware/hardware_adapter.h"

#include <stdio.h>
#include <string.h>

/* ---------------- 设备状态 (唯一数据源) ---------------- */

static device_state_t g_state = {
    .version = 1,
    .power = false,
    .brightness = 80,
    .color_temperature = 4000,
};

/* ---------------- 硬件操作 (TODO: 换成你的板级驱动) ---------------- */

/*
 * 真实硬件接入点。Jieli SDK 的 LED/PWM 接口按板子而定，
 * 常见做法：
 *   - 单色灯/指示灯:  GPIO 输出 (gpio_set_direction / gpio_write)
 *   - 调光灯:         PWM 占空比 (pwm_init / pwm_set_duty)
 *   - 双色温灯:       两路 PWM 混合
 * 下面用变量占位，替换为实际驱动调用即可。
 */
static void hw_set_power(bool on)
{
    /* TODO: gpio_write(LED_GPIO, on ? 1 : 0); */
    printf("[light1] hw power=%d\n", on);
}

static void hw_set_brightness(uint8_t value)
{
    /* TODO: pwm_set_duty(PWM_CH_LED, value); */
    printf("[light1] hw brightness=%u\n", value);
}

static void hw_set_color_temperature(uint16_t value)
{
    /* TODO: 双路 PWM 混合 (暖/冷) */
    printf("[light1] hw color_temp=%u\n", value);
}

const hardware_adapter_t g_hardware = {
    .set_power = hw_set_power,
    .set_brightness = hw_set_brightness,
    .set_color_temperature = hw_set_color_temperature,
    .get_temperature = NULL,   /* 无温度传感器 */
};

/* ---------------- 状态 → JSON (运行时 STATE 上报调用) ---------------- */

int myhome_device_state_json(char* out, int cap)
{
    return snprintf(out, (size_t)cap,
                    "{\"power\":%s,\"brightness\":%u,\"color_temperature\":%u}",
                    g_state.power ? "true" : "false", g_state.brightness,
                    g_state.color_temperature);
}

/* ---------------- 命令实现 (device_api.h 声明) ---------------- */

int light_set_power(bool power, char* response_json, int response_len)
{
    g_state.power = power;
    if (g_hardware.set_power) {
        g_hardware.set_power(power);
    }
    /* 状态变化 → 版本 +1 并推送 STATE 给手机 (§16) */
    g_state.version++;
    myhome_state_changed();

    return snprintf(response_json, (size_t)response_len,
                    "{\"status\":\"ok\",\"data\":{\"power\":%s}}",
                    power ? "true" : "false");
}

int light_set_brightness(uint8_t value, char* response_json, int response_len)
{
    g_state.brightness = value;
    if (g_hardware.set_brightness) {
        g_hardware.set_brightness(value);
    }
    g_state.version++;
    myhome_state_changed();
    device_publish_event("light1.state_changed", "{\"field\":\"brightness\"}");

    return snprintf(response_json, (size_t)response_len,
                    "{\"status\":\"ok\",\"data\":{\"brightness\":%u}}", value);
}

int light_set_color_temperature(uint16_t value, char* response_json,
                                int response_len)
{
    g_state.color_temperature = value;
    if (g_hardware.set_color_temperature) {
        g_hardware.set_color_temperature(value);
    }
    g_state.version++;
    myhome_state_changed();

    return snprintf(response_json, (size_t)response_len,
                    "{\"status\":\"ok\",\"data\":{\"color_temperature\":%u}}",
                    value);
}

/* ---------------- device_state.h 要求的 SDK 侧函数 ---------------- */

/** 直接改状态结构体后调用：同步版本并推送 (§37 状态模型)。 */
void device_state_changed(const device_state_t* state)
{
    if (state != NULL) {
        g_state = *state;
    }
    g_state.version++;
    myhome_state_changed();
}

/* ---------------- 应用启动 (在 app_main 或 BLE 初始化后调用) ---------------- */

void light1_app_init(void)
{
    /* MTU: 与 ble_vendor_set_default_att_mtu 设置一致；不确定时传 247 */
    myhome_init(247);

    /* 上电状态同步到硬件 */
    if (g_hardware.set_power) {
        g_hardware.set_power(g_state.power);
    }
    if (g_hardware.set_brightness) {
        g_hardware.set_brightness(g_state.brightness);
    }
    printf("[light1] app init done\n");
}
