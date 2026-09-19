#include "device_runtime.h"

#include <stdio.h>
#include <string.h>

#include "device_api.h"   /* 生成：device_handle_command */
#include "device_info.h"  /* 生成：DEVICE_TYPE / MODEL / 能力列表 */
#include "../codec/device_json.h"  /* SDK：字段提取 */

/* 与生成代码一致的错误码 (§10.5) */
#define ERR_INVALID_PARAMETER 3001
#define ERR_UNKNOWN_COMMAND   3002
#define ERR_RESOURCE_NOT_FOUND 5001

/* 内部：发送一条消息 (JSON 体，自动分片) */
static void send_message(device_runtime_t* rt, uint8_t frame_type,
                         const char* json)
{
    if (rt->hooks.send == NULL || json == NULL) {
        return;
    }
    const uint16_t len = (uint16_t)strlen(json);
    const uint16_t frames = frag_send_message(&rt->sender, rt->next_msg_id++,
                                              frame_type, (const uint8_t*)json,
                                              len, rt->hooks.send, rt->hooks.ctx);
    rt->tx_frames += frames;
}

/* 传输层 ACK (§9.1)：App 侧 ReliableChannel 依赖它，不发会触发重传 */
static void send_ack(device_runtime_t* rt, uint16_t msg_id)
{
    ble_frame_t ack;
    uint8_t buf[BLE_FRAME_HEADER_SIZE + 2 + BLE_FRAME_CRC_SIZE];
    uint8_t payload[2];
    payload[0] = (uint8_t)(msg_id >> 8);
    payload[1] = (uint8_t)(msg_id & 0xFF);
    ack.version = BLE_FRAME_VERSION;
    ack.type = FRAME_ACK;
    ack.flags = 0;
    ack.sequence = rt->sender.seq++;
    ack.length = 2;
    ack.payload = payload;
    const int out_len = ble_frame_encode(&ack, buf, sizeof(buf));
    if (out_len > 0 && rt->hooks.send != NULL) {
        rt->hooks.send(buf, (uint16_t)out_len, rt->hooks.ctx);
        rt->tx_frames++;
    }
}

/* 拼接状态 JSON：{"version":N,"state":{...}} */
static void send_state(device_runtime_t* rt)
{
    char state_json[DEVICE_RUNTIME_JSON_MAX];
    char out[DEVICE_RUNTIME_JSON_MAX + 64];
    if (rt->hooks.get_state_json == NULL) {
        return;
    }
    const int state_len =
        rt->hooks.get_state_json(state_json, (int)sizeof(state_json) - 1, rt->hooks.ctx);
    if (state_len <= 0) {
        return;
    }
    state_json[state_len] = '\0';
    snprintf(out, sizeof(out), "{\"version\":%lu,\"state\":%s}",
             (unsigned long)rt->state_version, state_json);
    send_message(rt, FRAME_STATE, out);
}

/* HELLO → HELLO_ACK (§39) */
static void handle_hello(device_runtime_t* rt, const char* json)
{
    char out[DEVICE_RUNTIME_JSON_MAX];
    uint32_t request_id = 0;
    (void)device_json_get_uint(json, "request_id", &request_id);

    int written = snprintf(
        out, sizeof(out),
        "{\"request_id\":%lu,\"protocol_version\":%d,\"device_type\":\"%s\","
        "\"device_model\":\"%s\",\"firmware_version\":\"%s\","
        "\"ui_version\":\"%s\",\"capabilities\":[",
        (unsigned long)request_id, DEVICE_PROTOCOL_VERSION, DEVICE_TYPE,
        DEVICE_MODEL, "0.1.0", DEVICE_UI_VERSION);
    for (int i = 0; i < DEVICE_CAPABILITY_COUNT && written > 0 &&
                    written < (int)sizeof(out) - 32;
         i++) {
        written += snprintf(out + written, sizeof(out) - (size_t)written,
                            "%s\"%s\"", i == 0 ? "" : ",", DEVICE_CAPABILITIES[i]);
    }
    snprintf(out + (written > 0 ? written : 0),
             written > 0 ? sizeof(out) - (size_t)written : 0, "]}");
    send_message(rt, FRAME_HELLO_ACK, out);
}

/* PING → PONG */
static void handle_ping(device_runtime_t* rt, const char* json)
{
    char out[64];
    uint32_t request_id = 0;
    (void)device_json_get_uint(json, "request_id", &request_id);
    snprintf(out, sizeof(out), "{\"request_id\":%lu}", (unsigned long)request_id);
    send_message(rt, FRAME_PONG, out);
}

/* STATE_REQUEST → STATE (§16.6) */
static void handle_state_request(device_runtime_t* rt)
{
    send_state(rt);
}

/* COMMAND → device_handle_command → RESPONSE (§10.2/§10.3) */
static void handle_command(device_runtime_t* rt, const char* json)
{
    char cmd[64];
    const char* params_ptr = NULL;
    uint16_t params_len = 0;
    uint32_t request_id = 0;
    char body[DEVICE_RUNTIME_JSON_MAX];
    char out[DEVICE_RUNTIME_JSON_MAX + 64];
    int body_len;

    if (device_json_get_uint(json, "request_id", &request_id) != 0) {
        return; /* 无 request_id 无法配对，丢弃 */
    }
    if (device_json_get_string(json, "cmd", cmd, sizeof(cmd)) != 0) {
        return;
    }
    if (device_json_get_raw(json, "params", &params_ptr, &params_len) != 0) {
        params_ptr = "{}"; /* 无参数命令 */
    }

    /* 参数子串非 NUL 结尾，复制到栈上再交给解析器 */
    char params[DEVICE_RUNTIME_JSON_MAX];
    if (params_ptr == NULL || params_len >= sizeof(params)) {
        return;
    }
    memcpy(params, params_ptr, params_len);
    params[params_len] = '\0';

    const int rc = device_handle_command(cmd, params, body, (int)sizeof(body));
    if (rc == ERR_INVALID_PARAMETER || rc == ERR_UNKNOWN_COMMAND) {
        snprintf(out, sizeof(out),
                 "{\"request_id\":%lu,\"status\":\"error\","
                 "\"error\":{\"code\":%d,\"message\":\"%s\"}}",
                 (unsigned long)request_id, rc,
                 rc == ERR_INVALID_PARAMETER ? "invalid parameter"
                                             : "unknown command");
        send_message(rt, FRAME_RESPONSE, out);
        return;
    }
    if (rc < 0) {
        snprintf(out, sizeof(out),
                 "{\"request_id\":%lu,\"status\":\"error\","
                 "\"error\":{\"code\":4001,\"message\":\"hardware error\"}}",
                 (unsigned long)request_id);
        send_message(rt, FRAME_RESPONSE, out);
        return;
    }

    /*
     * 硬件函数写入的是响应体 {"status":"ok","data":{...}}，
     * 这里补上 request_id 后整条发出 (跳过 body 开头的 '{')。
     */
    body_len = rc;
    if (body_len <= 0 || body[0] != '{') {
        snprintf(out, sizeof(out),
                 "{\"request_id\":%lu,\"status\":\"ok\",\"data\":{}}",
                 (unsigned long)request_id);
    } else {
        snprintf(out, sizeof(out), "{\"request_id\":%lu,%s",
                 (unsigned long)request_id, body + 1);
    }
    send_message(rt, FRAME_RESPONSE, out);
}

/* RESOURCE_REQUEST → RESOURCE_RESPONSE (§27 分块传输)
 *
 * App 按 offset 逐块拉取：每次请求回一个分块，天然流控 (不会冲击 BLE TX)。
 * 请求: {"request_id":N,"path":"ui.pkg","offset":0}
 * 响应: {"request_id":N,"status":"ok","offset":0,"total":1834,"data":"<base64>"}
 * App 累加至 offset + data.length >= total 即完成。
 */
#define RESOURCE_CHUNK_MAX 224 /* 单块原始字节 (base64 后 ~300B，单帧可承载) */

static void handle_resource_request(device_runtime_t* rt, const char* json)
{
    static const char b64[] =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    char path[96];
    char out[DEVICE_RUNTIME_JSON_MAX];
    uint32_t request_id = 0;
    uint32_t offset = 0;
    uint8_t chunk[RESOURCE_CHUNK_MAX];
    int total;
    int read;

    (void)device_json_get_uint(json, "request_id", &request_id);
    (void)device_json_get_uint(json, "offset", &offset);
    if (device_json_get_string(json, "path", path, sizeof(path)) != 0) {
        return;
    }

    if (rt->hooks.get_resource_size == NULL || rt->hooks.get_resource_chunk == NULL) {
        snprintf(out, sizeof(out),
                 "{\"request_id\":%lu,\"status\":\"error\","
                 "\"error\":{\"code\":%d,\"message\":\"resource not found\"}}",
                 (unsigned long)request_id, ERR_RESOURCE_NOT_FOUND);
        send_message(rt, FRAME_RESOURCE_RESP, out);
        return;
    }

    total = rt->hooks.get_resource_size(path, rt->hooks.ctx);
    if (total < 0 || offset > (uint32_t)total) {
        snprintf(out, sizeof(out),
                 "{\"request_id\":%lu,\"status\":\"error\","
                 "\"error\":{\"code\":%d,\"message\":\"resource not found\"}}",
                 (unsigned long)request_id, ERR_RESOURCE_NOT_FOUND);
        send_message(rt, FRAME_RESOURCE_RESP, out);
        return;
    }

    read = rt->hooks.get_resource_chunk(path, offset, chunk, RESOURCE_CHUNK_MAX,
                                        rt->hooks.ctx);
    if (read < 0) {
        snprintf(out, sizeof(out),
                 "{\"request_id\":%lu,\"status\":\"error\","
                 "\"error\":{\"code\":%d,\"message\":\"resource read error\"}}",
                 (unsigned long)request_id, ERR_RESOURCE_NOT_FOUND);
        send_message(rt, FRAME_RESOURCE_RESP, out);
        return;
    }

    /* base64 编码本块并组包 */
    const int prefix = snprintf(
        out, sizeof(out),
        "{\"request_id\":%lu,\"status\":\"ok\",\"offset\":%lu,\"total\":%lu,"
        "\"data\":\"",
        (unsigned long)request_id, (unsigned long)offset, (unsigned long)total);
    int pos = prefix;
    for (int i = 0; i < read && pos < (int)sizeof(out) - 8; i += 3) {
        const uint32_t b0 = chunk[i];
        const uint32_t b1 = (i + 1 < read) ? chunk[i + 1] : 0;
        const uint32_t b2 = (i + 2 < read) ? chunk[i + 2] : 0;
        const uint32_t triple = (b0 << 16) | (b1 << 8) | b2;
        out[pos++] = b64[(triple >> 18) & 0x3F];
        out[pos++] = b64[(triple >> 12) & 0x3F];
        out[pos++] = (i + 1 < read) ? b64[(triple >> 6) & 0x3F] : '=';
        out[pos++] = (i + 2 < read) ? b64[triple & 0x3F] : '=';
    }
    out[pos++] = '"';
    out[pos++] = '}';
    out[pos] = '\0';
    send_message(rt, FRAME_RESOURCE_RESP, out);
}

/* 组装完成的消息分发 */
static void on_message(uint16_t msg_id, uint8_t frame_type, const uint8_t* data,
                       uint16_t len, void* ctx)
{
    device_runtime_t* rt = (device_runtime_t*)ctx;
    char json[DEVICE_RUNTIME_JSON_MAX];

    send_ack(rt, msg_id); /* 先 ACK，再处理 (§9.1) */

    if (len >= sizeof(json)) {
        return; /* 超长消息：忽略 (容量宏可调大) */
    }
    memcpy(json, data, len);
    json[len] = '\0';

    switch (frame_type) {
    case FRAME_HELLO:
        handle_hello(rt, json);
        break;
    case FRAME_PING:
        handle_ping(rt, json);
        break;
    case FRAME_STATE_REQUEST:
        handle_state_request(rt);
        break;
    case FRAME_COMMAND:
        handle_command(rt, json);
        break;
    case FRAME_RESOURCE_REQ:
        handle_resource_request(rt, json);
        break;
    default:
        break; /* 其余类型 (RESPONSE/EVENT/STATE/PATCH) 设备侧不处理 */
    }
}

/* 组装完成后的分片超时清理通知 */
static void on_discard(uint16_t msg_id, const char* reason, void* ctx)
{
    device_runtime_t* rt = (device_runtime_t*)ctx;
    (void)reason;
    rt->bad_frames++;
    (void)msg_id;
}

/* 重复分片 (发送端重发)：重发 ACK，避免发送端重试耗尽 (§7.4) */
static void on_duplicate(uint16_t msg_id, void* ctx)
{
    device_runtime_t* rt = (device_runtime_t*)ctx;
    rt->duplicate_frames++;
    send_ack(rt, msg_id);
}

/* 帧流解码完成一帧 */
static void on_frame(const ble_frame_t* frame, void* ctx)
{
    device_runtime_t* rt = (device_runtime_t*)ctx;
    rt->rx_frames++;

    switch (frame->type) {
    case FRAME_ACK:
    case FRAME_NACK:
        /* 我方发出的消息被 App 确认 —— MVP 不做重传跟踪 */
        break;
    case FRAME_COMMAND:
    case FRAME_HELLO:
    case FRAME_PING:
    case FRAME_STATE_REQUEST:
    case FRAME_RESOURCE_REQ:
        frag_assembler_add(&rt->assembler, frame);
        break;
    default:
        break;
    }
}

static void on_frame_error(const char* reason, void* ctx)
{
    device_runtime_t* rt = (device_runtime_t*)ctx;
    (void)reason;
    rt->bad_frames++;
}

void device_runtime_init(device_runtime_t* rt, const device_runtime_hooks_t* hooks,
                         uint16_t mtu)
{
    if (rt == NULL || hooks == NULL) {
        return;
    }
    memset(rt, 0, sizeof(*rt));
    rt->hooks = *hooks;
    frag_sender_init(&rt->sender, mtu);
    frag_assembler_init(&rt->assembler, DEVICE_RUNTIME_ASSEMBLE_TIMEOUT_MS,
                        on_message, on_discard, on_duplicate, rt);
    ble_stream_decoder_init(&rt->decoder, on_frame, on_frame_error, rt);
    rt->next_msg_id = 1;
    rt->state_version = 1;
}

void device_runtime_on_bytes(device_runtime_t* rt, const uint8_t* data,
                             uint16_t len)
{
    if (rt == NULL) {
        return;
    }
    ble_stream_decoder_add(&rt->decoder, data, len);
}

void device_runtime_tick(device_runtime_t* rt, uint32_t now_ms)
{
    if (rt == NULL) {
        return;
    }
    (void)frag_assembler_tick(&rt->assembler, now_ms);
}

void device_runtime_notify_state_changed(device_runtime_t* rt)
{
    if (rt == NULL) {
        return;
    }
    rt->state_version++;
    send_state(rt);
}

void device_runtime_send_event(device_runtime_t* rt, const char* name,
                               const char* data_json)
{
    char out[DEVICE_RUNTIME_JSON_MAX];
    if (rt == NULL || name == NULL) {
        return;
    }
    snprintf(out, sizeof(out), "{\"event\":\"%s\",\"data\":%s}", name,
             data_json == NULL ? "{}" : data_json);
    send_message(rt, FRAME_EVENT, out);
}

void device_runtime_reset(device_runtime_t* rt)
{
    if (rt == NULL) {
        return;
    }
    ble_stream_decoder_reset(&rt->decoder);
    frag_assembler_reset(&rt->assembler);
}

uint32_t device_runtime_state_version(const device_runtime_t* rt)
{
    return rt == NULL ? 0 : rt->state_version;
}
