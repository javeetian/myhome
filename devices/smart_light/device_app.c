/* Smart Light 硬件实现示例 (WORK_V3 §45 开发者代码)。
 * 开发者将本文件 (及 generated/) 拷贝到设备 SDK 的 app/ 目录后编译；
 * 真实硬件替换 g_hardware 的实现为 PWM/GPIO/传感器驱动调用。 */
#include "hardware_adapter.h"

#include <stdio.h>

/* ---- 模拟硬件状态 (真实设备替换为驱动调用) ---- */
static bool s_power = false;
static uint8_t s_brightness = 80;
static uint16_t s_color_temperature = 4000;

static void hw_set_power(bool value) { s_power = value; }
static void hw_set_brightness(uint8_t value) { s_brightness = value; }
static void hw_set_color_temperature(uint16_t value) {
    s_color_temperature = value;
}
static uint16_t hw_get_temperature(void) { return 250; /* 25.0°C */ }

const hardware_adapter_t g_hardware = {
    .set_power = hw_set_power,
    .set_brightness = hw_set_brightness,
    .set_color_temperature = hw_set_color_temperature,
    .get_temperature = hw_get_temperature,
};

/* ---- 实现 generated/device_api.h 的命令处理 (§45) ---- */

int light_set_power(bool power, char* response_json, int response_len) {
    g_hardware.set_power(power);
    return snprintf(response_json, (size_t)response_len,
                    "{\"status\":\"ok\",\"data\":{\"power\":%s}}",
                    power ? "true" : "false");
}

int light_set_brightness(uint8_t value, char* response_json, int response_len) {
    g_hardware.set_brightness(value);
    return snprintf(response_json, (size_t)response_len,
                    "{\"status\":\"ok\",\"data\":{\"brightness\":%u}}", value);
}

int light_set_color_temperature(uint16_t value, char* response_json,
                                int response_len) {
    g_hardware.set_color_temperature(value);
    return snprintf(response_json, (size_t)response_len,
                    "{\"status\":\"ok\",\"data\":{\"color_temperature\":%u}}",
                    value);
}
