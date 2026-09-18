/**
 * C SDK 一致性测试 (WORK_V3 §34)：
 * 1. 基础层 golden 向量 (CRC / Frame / JSON) 与 Dart 逐字节一致
 * 2. 运行时层：喂入 Dart 侧生成的真实帧字节 → 校验 ACK / 响应行为
 *
 * golden 字节由 Dart 实现生成 (tools/gen_c_golden.dart)，
 * 更新 Dart 协议后需重新生成并同步本文件。
 */
#include "../core/protocol/crc16.h"
#include "../core/protocol/ble_frame.h"
#include "../core/codec/device_json.h"
#include "../core/runtime/ble_stream_decoder.h"
#include "../core/runtime/fragment.h"
#include "../core/runtime/device_runtime.h"
#include "../hardware/hardware_adapter.h"
#include "device_info.h"  /* 测试桩 (对应 generated/) */

#include <stdio.h>
#include <string.h>

static int g_failures = 0;

static void check(int ok, const char* name) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", name);
    if (!ok) g_failures++;
}

/* ---------------- 1. 基础层 golden ---------------- */

static void test_crc_anchor(void) {
    const uint8_t data[] = "123456789";
    check(crc16_ccitt(data, sizeof(data) - 1) == 0x29B1,
          "crc anchor 123456789 -> 0x29B1");
}

static void test_frame_golden(void) {
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
    check(total == (int)sizeof(golden) && memcmp(out, golden, sizeof(golden)) == 0,
          "frame encode == dart golden bytes");

    ble_frame_t decoded;
    const int decoded_len = ble_frame_decode(golden, sizeof(golden), &decoded);
    check(decoded_len == (int)sizeof(golden) && decoded.type == FRAME_COMMAND &&
              decoded.sequence == 100 && decoded.length == 5 &&
              memcmp(decoded.payload, "hello", 5) == 0,
          "frame decode round-trip");

    uint8_t corrupted[sizeof(golden)];
    memcpy(corrupted, golden, sizeof(golden));
    corrupted[7] ^= 0xFF;
    check(ble_frame_decode(corrupted, sizeof(corrupted), &decoded) == -2,
          "frame decode detects crc error");
    check(ble_frame_decode(golden, sizeof(golden) - 1, &decoded) == -1,
          "frame decode rejects wrong length");
}

static void test_json_getters(void) {
    const char* params = "{\"power\": true, \"value\": 80, \"temp\": 25.5, \"name\": \"light\", \"obj\": {\"a\": 1}}";
    bool b = false;
    uint32_t u = 0;
    float f = 0;
    char s[16] = {0};
    const char* raw = NULL;
    uint16_t raw_len = 0;

    check(device_json_get_bool(params, "power", &b) == 0 && b == true, "json get bool");
    check(device_json_get_uint(params, "value", &u) == 0 && u == 80, "json get uint");
    check(device_json_get_float(params, "temp", &f) == 0 && f > 25.4f && f < 25.6f,
          "json get float");
    check(device_json_get_string(params, "name", s, sizeof(s)) == 0 &&
              strcmp(s, "light") == 0,
          "json get string");
    check(device_json_get_uint(params, "missing", &u) != 0, "json missing field rejected");
    check(device_json_get_uint(params, "power", &u) != 0, "json type mismatch rejected");
    check(device_json_get_raw(params, "obj", &raw, &raw_len) == 0 && raw_len == 8 &&
              memcmp(raw, "{\"a\": 1}", 8) == 0,
          "json get raw object");
}

/* ---------------- 2. 帧流解码 (半包/粘包) ---------------- */

static int g_frame_count = 0;
static uint8_t g_last_type = 0;
static uint16_t g_last_seq = 0;

static void on_decoded(const ble_frame_t* frame, void* ctx) {
    (void)ctx;
    g_frame_count++;
    g_last_type = frame->type;
    g_last_seq = frame->sequence;
}

static void test_stream_decoder(void) {
    /* Dart golden: HELLO 帧 (37B payload) + PING 帧 (16B payload) 拼在一起 */
    static const uint8_t golden_hello[] = {
        0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x2d, 0x00, 0x01, 0x00, 0x00, 0x00,
        0x01, 0x00, 0x25, 0x7b, 0x22, 0x72, 0x65, 0x71, 0x75, 0x65, 0x73, 0x74,
        0x5f, 0x69, 0x64, 0x22, 0x3a, 0x31, 0x2c, 0x22, 0x70, 0x72, 0x6f, 0x74,
        0x6f, 0x63, 0x6f, 0x6c, 0x5f, 0x76, 0x65, 0x72, 0x73, 0x69, 0x6f, 0x6e,
        0x22, 0x3a, 0x31, 0x7d, 0xe8, 0x6d,
    };
    static const uint8_t golden_ping[] = {
        0x01, 0x22, 0x00, 0x00, 0x01, 0x00, 0x18, 0x00, 0x02, 0x00, 0x00, 0x00,
        0x01, 0x00, 0x10, 0x7b, 0x22, 0x72, 0x65, 0x71, 0x75, 0x65, 0x73, 0x74,
        0x5f, 0x69, 0x64, 0x22, 0x3a, 0x32, 0x7d, 0xe1, 0xa7,
    };

    ble_stream_decoder_t dec;
    ble_stream_decoder_init(&dec, on_decoded, NULL, NULL);

    /* 半包：分 3 段喂入同一帧 */
    g_frame_count = 0;
    ble_stream_decoder_add(&dec, golden_hello, 10);
    check(g_frame_count == 0, "stream: partial frame buffered");
    ble_stream_decoder_add(&dec, golden_hello + 10, 20);
    check(g_frame_count == 0, "stream: still partial");
    ble_stream_decoder_add(&dec, golden_hello + 30, 24);
    check(g_frame_count == 1 && g_last_seq == 0,
          "stream: frame decoded after last chunk");

    /* 粘包：一次喂入两帧 */
    g_frame_count = 0;
    uint8_t merged[sizeof(golden_hello) + sizeof(golden_ping)];
    memcpy(merged, golden_hello, sizeof(golden_hello));
    memcpy(merged + sizeof(golden_hello), golden_ping, sizeof(golden_ping));
    ble_stream_decoder_add(&dec, merged, sizeof(merged));
    check(g_frame_count == 2 && g_last_type == FRAME_PING && g_last_seq == 1,
          "stream: merged frames both decoded");

    /* 坏帧 (翻转 CRC) 按长度跳过，后续帧仍能解出 */
    g_frame_count = 0;
    uint8_t bad[sizeof(golden_ping)];
    memcpy(bad, golden_ping, sizeof(golden_ping));
    bad[sizeof(bad) - 1] ^= 0xFF;
    ble_stream_decoder_add(&dec, bad, sizeof(bad));
    check(g_frame_count == 0, "stream: bad crc frame dropped");
    ble_stream_decoder_add(&dec, golden_ping, sizeof(golden_ping));
    check(g_frame_count == 1, "stream: realigns after bad frame");
}

/* ---------------- 3. 分片器 / 组装器 ---------------- */

static uint8_t g_tx_buf[4096];
static uint16_t g_tx_len = 0;
static int g_tx_count = 0;

static void tx_collect(const uint8_t* bytes, uint16_t len, void* ctx) {
    (void)ctx;
    if ((uint32_t)g_tx_len + len <= sizeof(g_tx_buf)) {
        memcpy(g_tx_buf + g_tx_len, bytes, len);
        g_tx_len += len;
    }
    g_tx_count++;
}

static uint8_t g_rx_msg[1024];
static uint16_t g_rx_msg_len = 0;
static uint16_t g_rx_msg_id = 0;
static int g_rx_complete = 0;

static void on_assembled(uint16_t msg_id, uint8_t frame_type,
                         const uint8_t* data, uint16_t len, void* ctx) {
    (void)frame_type;
    (void)ctx;
    memcpy(g_rx_msg, data, len);
    g_rx_msg_len = len;
    g_rx_msg_id = msg_id;
    g_rx_complete++;
}

static void test_fragment_roundtrip(void) {
    /* 300 字节消息 → MTU 247 分片 → 组装还原 */
    uint8_t payload[300];
    for (int i = 0; i < 300; i++) {
        payload[i] = (uint8_t)(i & 0xFF);
    }

    frag_sender_t sender;
    frag_sender_init(&sender, 247);
    check(frag_max_data_size(&sender) == 227, "frag: max data size = mtu-3-7-8-2");

    g_tx_len = 0;
    g_tx_count = 0;
    const uint16_t frames = frag_send_message(&sender, 7, FRAME_COMMAND, payload,
                                              sizeof(payload), tx_collect, NULL);
    check(frames == 2 && g_tx_count == 2, "frag: 300B -> 2 frames");

    /* 组装回原消息 (按 LENGTH 切帧后逐帧喂入组装器) */
    frag_assembler_t asm_;
    frag_assembler_init(&asm_, 0, on_assembled, NULL, NULL, NULL);
    g_rx_complete = 0;

    uint16_t offset = 0;
    while (offset + BLE_FRAME_HEADER_SIZE + BLE_FRAME_CRC_SIZE <= g_tx_len) {
        const uint16_t plen =
            (uint16_t)(((uint16_t)g_tx_buf[offset + 5] << 8) | g_tx_buf[offset + 6]);
        const uint16_t flen =
            (uint16_t)(BLE_FRAME_HEADER_SIZE + plen + BLE_FRAME_CRC_SIZE);
        if ((uint32_t)offset + flen > g_tx_len) {
            break;
        }
        ble_frame_t frame;
        if (ble_frame_decode(g_tx_buf + offset, flen, &frame) > 0) {
            frag_assembler_add(&asm_, &frame);
        }
        offset = (uint16_t)(offset + flen);
    }
    check(g_rx_complete == 1 && g_rx_msg_id == 7 && g_rx_msg_len == 300 &&
              memcmp(g_rx_msg, payload, 300) == 0,
          "frag: 300B message reassembled byte-identical");
}

/* ---------------- 4. 运行时端到端 (Dart golden 输入) ---------------- */

static uint8_t g_rt_tx[4096];
static uint16_t g_rt_tx_len = 0;

static void rt_send(const uint8_t* data, uint16_t len, void* ctx) {
    (void)ctx;
    if ((uint32_t)g_rt_tx_len + len <= sizeof(g_rt_tx)) {
        memcpy(g_rt_tx + g_rt_tx_len, data, len);
        g_rt_tx_len += len;
    }
}

static int rt_get_state(char* out, int cap, void* ctx) {
    (void)ctx;
    return snprintf(out, (size_t)cap, "{\"power\":false,\"brightness\":50}");
}

/* 测试用命令处理 (替代生成的 device_handle_command) */
int device_handle_command(const char* cmd, const char* params_json,
                          char* response_json, int response_len) {
    if (strcmp(cmd, "light.set_power") == 0) {
        bool power = false;
        if (device_json_get_bool(params_json, "power", &power) != 0) {
            return 3001;
        }
        return snprintf(response_json, (size_t)response_len,
                        "{\"status\":\"ok\",\"data\":{\"power\":%s}}",
                        power ? "true" : "false");
    }
    if (strcmp(cmd, "light.set_brightness") == 0) {
        uint32_t value = 0;
        if (device_json_get_uint(params_json, "value", &value) != 0) {
            return 3001;
        }
        if (value > 100) {
            return 3001;
        }
        return snprintf(response_json, (size_t)response_len,
                        "{\"status\":\"ok\",\"data\":{\"brightness\":%lu}}",
                        (unsigned long)value);
    }
    return 3002;
}

/*
 * 发送缓冲按帧遍历：从帧头 LENGTH 计算帧长切片再解码。
 * (ble_frame_decode 要求恰好一帧，缓冲含多帧时必须先切分)
 */
typedef void (*frame_visitor_fn)(const ble_frame_t* frame, void* ctx);

static void walk_tx_frames(frame_visitor_fn visit, void* ctx) {
    uint16_t offset = 0;
    while (offset + BLE_FRAME_HEADER_SIZE + BLE_FRAME_CRC_SIZE <= g_rt_tx_len) {
        const uint16_t payload_len =
            (uint16_t)(((uint16_t)g_rt_tx[offset + 5] << 8) | g_rt_tx[offset + 6]);
        const uint16_t frame_len =
            (uint16_t)(BLE_FRAME_HEADER_SIZE + payload_len + BLE_FRAME_CRC_SIZE);
        if ((uint32_t)offset + frame_len > g_rt_tx_len) {
            break;
        }
        ble_frame_t frame;
        if (ble_frame_decode(g_rt_tx + offset, frame_len, &frame) > 0) {
            visit(&frame, ctx);
        }
        offset = (uint16_t)(offset + frame_len);
    }
}

static char* g_find_out;
static int g_find_cap;
static int g_find_type;
static int g_find_found;

static void find_visitor(const ble_frame_t* frame, void* ctx) {
    (void)ctx;
    if (g_find_found || frame->type != g_find_type || frame->length < 8) {
        return;
    }
    const uint16_t json_len = (uint16_t)(frame->length - 8); /* 跳过 Fragment 头 */
    const uint16_t copy = json_len < (uint16_t)(g_find_cap - 1)
                              ? json_len
                              : (uint16_t)(g_find_cap - 1);
    memcpy(g_find_out, frame->payload + 8, copy);
    g_find_out[copy] = '\0';
    g_find_found = 1;
}

/* 查找指定类型帧 (返回去 Fragment 头后的 payload 副本) */
static int find_frame(uint8_t type, char* out, int cap) {
    g_find_out = out;
    g_find_cap = cap;
    g_find_type = type;
    g_find_found = 0;
    walk_tx_frames(find_visitor, NULL);
    return g_find_found;
}

static int g_ack_count;

static void ack_visitor(const ble_frame_t* frame, void* ctx) {
    (void)ctx;
    if (frame->type == FRAME_ACK) {
        g_ack_count++;
    }
}

static int count_ack(void) {
    g_ack_count = 0;
    walk_tx_frames(ack_visitor, NULL);
    return g_ack_count;
}

static void test_runtime_end_to_end(void) {
    /* Dart 侧生成的 golden 帧 (见 tools/gen_c_golden.dart) */
    static const uint8_t g_hello[] = {
        0x01, 0x20, 0x00, 0x00, 0x00, 0x00, 0x2d, 0x00, 0x01, 0x00, 0x00, 0x00,
        0x01, 0x00, 0x25, 0x7b, 0x22, 0x72, 0x65, 0x71, 0x75, 0x65, 0x73, 0x74,
        0x5f, 0x69, 0x64, 0x22, 0x3a, 0x31, 0x2c, 0x22, 0x70, 0x72, 0x6f, 0x74,
        0x6f, 0x63, 0x6f, 0x6c, 0x5f, 0x76, 0x65, 0x72, 0x73, 0x69, 0x6f, 0x6e,
        0x22, 0x3a, 0x31, 0x7d, 0xa3, 0x76,
    };
    static const uint8_t g_ping[] = {
        0x01, 0x22, 0x00, 0x00, 0x01, 0x00, 0x18, 0x00, 0x02, 0x00, 0x00, 0x00,
        0x01, 0x00, 0x10, 0x7b, 0x22, 0x72, 0x65, 0x71, 0x75, 0x65, 0x73, 0x74,
        0x5f, 0x69, 0x64, 0x22, 0x3a, 0x32, 0x7d, 0xe1, 0xa7,
    };
    static const uint8_t g_state_req[] = {
        0x01, 0x32, 0x00, 0x00, 0x02, 0x00, 0x18, 0x00, 0x03, 0x00, 0x00, 0x00,
        0x01, 0x00, 0x10, 0x7b, 0x22, 0x72, 0x65, 0x71, 0x75, 0x65, 0x73, 0x74,
        0x5f, 0x69, 0x64, 0x22, 0x3a, 0x33, 0x7d, 0x19, 0xc7,
    };
    static const uint8_t g_cmd[] = {
        0x01, 0x01, 0x00, 0x00, 0x03, 0x00, 0x4c, 0x00, 0x04, 0x00, 0x00, 0x00,
        0x01, 0x00, 0x44, 0x7b, 0x22, 0x72, 0x65, 0x71, 0x75, 0x65, 0x73, 0x74,
        0x5f, 0x69, 0x64, 0x22, 0x3a, 0x31, 0x30, 0x2c, 0x22, 0x63, 0x6d, 0x64,
        0x22, 0x3a, 0x22, 0x6c, 0x69, 0x67, 0x68, 0x74, 0x2e, 0x73, 0x65, 0x74,
        0x5f, 0x62, 0x72, 0x69, 0x67, 0x68, 0x74, 0x6e, 0x65, 0x73, 0x73, 0x22,
        0x2c, 0x22, 0x70, 0x61, 0x72, 0x61, 0x6d, 0x73, 0x22, 0x3a, 0x7b, 0x22,
        0x76, 0x61, 0x6c, 0x75, 0x65, 0x22, 0x3a, 0x35, 0x30, 0x7d, 0x7d, 0x12,
        0x18,
    };

    device_runtime_t rt;
    device_runtime_hooks_t hooks;
    memset(&hooks, 0, sizeof(hooks));
    hooks.send = rt_send;
    hooks.get_state_json = rt_get_state;
    device_runtime_init(&rt, &hooks, 247);

    char json[512];

    /* HELLO → ACK + HELLO_ACK */
    g_rt_tx_len = 0;
    device_runtime_on_bytes(&rt, g_hello, sizeof(g_hello));
    check(count_ack() == 1, "runtime: HELLO gets ACK");
    check(find_frame(FRAME_HELLO_ACK, json, sizeof(json)) &&
              strstr(json, "\"request_id\":1") != NULL &&
              strstr(json, DEVICE_TYPE) != NULL,
          "runtime: HELLO_ACK carries request_id + device_type");

    /* PING → ACK + PONG */
    g_rt_tx_len = 0;
    device_runtime_on_bytes(&rt, g_ping, sizeof(g_ping));
    check(count_ack() == 1, "runtime: PING gets ACK");
    check(find_frame(FRAME_PONG, json, sizeof(json)) &&
              strcmp(json, "{\"request_id\":2}") == 0,
          "runtime: PONG echoes request_id");

    /* STATE_REQUEST → ACK + STATE */
    g_rt_tx_len = 0;
    device_runtime_on_bytes(&rt, g_state_req, sizeof(g_state_req));
    check(count_ack() == 1, "runtime: STATE_REQUEST gets ACK");
    check(find_frame(FRAME_STATE, json, sizeof(json)) &&
              strstr(json, "\"version\":1") != NULL &&
              strstr(json, "\"brightness\":50") != NULL,
          "runtime: STATE carries version + app state json");

    /* COMMAND → ACK + RESPONSE (request_id 回填) */
    g_rt_tx_len = 0;
    device_runtime_on_bytes(&rt, g_cmd, sizeof(g_cmd));
    check(count_ack() == 1, "runtime: COMMAND gets ACK");
    check(find_frame(FRAME_RESPONSE, json, sizeof(json)) &&
              strstr(json, "\"request_id\":10") != NULL &&
              strstr(json, "\"status\":\"ok\"") != NULL &&
              strstr(json, "\"brightness\":50") != NULL,
          "runtime: RESPONSE merges request_id + hardware body");

    /* 重复帧 (发送端重发) → 重发 ACK */
    g_rt_tx_len = 0;
    device_runtime_on_bytes(&rt, g_cmd, sizeof(g_cmd));
    check(count_ack() == 1 && rt.duplicate_frames == 1,
          "runtime: duplicate frame re-sends ACK (no re-execute)");

    /* 未知命令 → 3002 错误响应 */
    const char* unknown =
        "{\"request_id\":11,\"cmd\":\"light.fly\",\"params\":{}}";
    device_runtime_t rt2;
    device_runtime_init(&rt2, &hooks, 247);
    g_rt_tx_len = 0;
    frag_sender_t s2;
    frag_sender_init(&s2, 247);
    g_tx_len = 0;
    g_tx_count = 0;
    frag_send_message(&s2, 9, FRAME_COMMAND, (const uint8_t*)unknown,
                      (uint16_t)strlen(unknown), tx_collect, NULL);
    device_runtime_on_bytes(&rt2, g_tx_buf, g_tx_len);
    check(find_frame(FRAME_RESPONSE, json, sizeof(json)) &&
              strstr(json, "\"code\":3002") != NULL,
          "runtime: unknown command -> error 3002");
}

int main(void) {
    test_crc_anchor();
    test_frame_golden();
    test_json_getters();
    test_stream_decoder();
    test_fragment_roundtrip();
    test_runtime_end_to_end();
    printf("%s (%d failures)\n", g_failures == 0 ? "ALL PASS" : "FAILED",
           g_failures);
    return g_failures == 0 ? 0 : 1;
}
