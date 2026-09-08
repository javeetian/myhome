/** Auto-generated. 设备状态结构体 (WORK_V3 §37 状态模型)。 */
#ifndef DEVICE_STATE_H
#define DEVICE_STATE_H

#include <stdbool.h>
#include <stdint.h>

typedef struct {
  uint32_t version;
  bool power;
  uint8_t brightness;
  uint16_t color_temperature;
} device_state_t;

/* SDK core 提供：状态变更后调用 (版本递增 + Patch 生成) */
void device_state_changed(const device_state_t* state);

#endif /* DEVICE_STATE_H */
