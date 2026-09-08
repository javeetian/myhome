/* Hardware Adapter (WORK_V3 §27/§31)：
 * 设备业务逻辑与硬件驱动分离。开发者实现真实硬件驱动
 * (device_app.c / hardware.c)；PC 模拟侧对应 Dart 的
 * VirtualHardware (lib/device/virtual_hardware.dart)，两者字段一一对应。 */
#ifndef HARDWARE_ADAPTER_H
#define HARDWARE_ADAPTER_H

#include <stdbool.h>
#include <stdint.h>

typedef struct {
    /* 电源开关 (GPIO) */
    void (*set_power)(bool value);
    /* 亮度 (PWM, 0-100) */
    void (*set_brightness)(uint8_t value);
    /* 色温 (PWM, 2700-6500) */
    void (*set_color_temperature)(uint16_t value);
    /* 温度采样 (传感器, 0.1°C 单位) */
    uint16_t (*get_temperature)(void);
} hardware_adapter_t;

/* 由 device_app.c 提供：当前硬件适配器实例 */
extern const hardware_adapter_t g_hardware;

#endif /* HARDWARE_ADAPTER_H */
