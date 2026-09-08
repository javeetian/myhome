/* C SDK 一致性测试：与 Dart 实现的 golden 向量逐字节比对。
 * golden 向量由 Dart 实现生成 (Phase 26 执行记录)。 */
#include "../core/protocol/crc16.h"
#include "../core/protocol/ble_frame.h"
#include "../core/codec/device_json.h"
#include "../hardware/hardware_adapter.h"

#include <stdio.h>
#include <string.h>

static int g_failures = 0;

static void check(int ok, const char* name) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", name);
    if (!ok) g_failures++;
}

static void test_crc_anchor(void) {
    /* 已知答案锚点：CRC16/CCITT-FALSE("123456789") = 0x29B1 */
    const uint8_t data[] = "123456789";
    check(crc16_ccitt(data, sizeof(data) - 1) == 0x29B1, "crc anchor 123456789 -> 0x29B1");
}

static void test_frame_golden(void) {
    /* Dart golden: VER=1 TYPE=0x01 FLAGS=0 SEQ=100 LEN=5 "hello" */
    static const uint8_t golden[] = {
        0x01, 0x01, 0x00, 0x00, 0x64, 0x00, 0x05,
        'h', 'e', 'l', 'l', 'o',
        0x5d, 0x73,
    };
    uint8_t out[64];
    ble_frame_t frame = {
        .version = 1, .type = FRAME_COMMAND, .flags = 0,
        .sequence = 100, .length = 5, .payload = (const uint8_t*)"hello",
    };
    const int total = ble_frame_encode(&frame, out, sizeof(out));
    check(total == (int)sizeof(golden) &&
              memcmp(out, golden, sizeof(golden)) == 0,
          "frame encode == dart golden bytes");

    ble_frame_t decoded;
    const int decoded_len = ble_frame_decode(golden, sizeof(golden), &decoded);
    check(decoded_len == (int)sizeof(golden) &&
              decoded.type == FRAME_COMMAND && decoded.sequence == 100 &&
              decoded.length == 5 &&
              memcmp(decoded.payload, "hello", 5) == 0,
          "frame decode round-trip");

    /* CRC 错误检测：翻转 payload 一个字节 */
    uint8_t corrupted[sizeof(golden)];
    memcpy(corrupted, golden, sizeof(golden));
    corrupted[7] ^= 0xFF;
    check(ble_frame_decode(corrupted, sizeof(corrupted), &decoded) == -2,
          "frame decode detects crc error");

    /* 长度不符 */
    check(ble_frame_decode(golden, sizeof(golden) - 1, &decoded) == -1,
          "frame decode rejects wrong length");
}

static void test_json_getters(void) {
    const char* params = "{\"power\": true, \"value\": 80, \"temp\": 25.5, \"name\": \"light\"}";
    bool b = false;
    uint32_t u = 0;
    float f = 0;
    char s[16] = {0};

    check(device_json_get_bool(params, "power", &b) == 0 && b == true,
          "json get bool");
    check(device_json_get_uint(params, "value", &u) == 0 && u == 80,
          "json get uint");
    check(device_json_get_float(params, "temp", &f) == 0 && f > 25.4f && f < 25.6f,
          "json get float");
    check(device_json_get_string(params, "name", s, sizeof(s)) == 0 &&
              strcmp(s, "light") == 0,
          "json get string");
    check(device_json_get_uint(params, "missing", &u) != 0,
          "json missing field rejected");
    check(device_json_get_uint(params, "power", &u) != 0,
          "json type mismatch rejected");
}

int main(void) {
    test_crc_anchor();
    test_frame_golden();
    test_json_getters();
    printf("%s (%d failures)\n",
           g_failures == 0 ? "ALL PASS" : "FAILED", g_failures);
    return g_failures == 0 ? 0 : 1;
}
