#include "fragment.h"

#include <string.h>

/* ---------------- 发送方向 ---------------- */

void frag_sender_init(frag_sender_t* s, uint16_t mtu)
{
    if (s == NULL) {
        return;
    }
    s->mtu = mtu;
    s->seq = 0;
}

uint16_t frag_max_data_size(const frag_sender_t* s)
{
    if (s == NULL) {
        return 0;
    }
    /* Frame头(7) + Fragment头(8) + DATA + CRC(2) ≤ mtu - 3 (ATT 写入头) */
    const int32_t available = (int32_t)s->mtu - 3 - BLE_FRAME_HEADER_SIZE -
                              FRAGMENT_HEADER_SIZE - BLE_FRAME_CRC_SIZE;
    return available > 0 ? (uint16_t)available : 0;
}

uint16_t frag_send_message(frag_sender_t* s, uint16_t msg_id, uint8_t frame_type,
                           const uint8_t* data, uint16_t len,
                           frag_send_fn send, void* ctx)
{
    if (s == NULL || send == NULL) {
        return 0;
    }
    const uint16_t max_data = frag_max_data_size(s);
    if (max_data == 0) {
        return 0;
    }
    const uint16_t total =
        len == 0 ? 1 : (uint16_t)((len + max_data - 1) / max_data);

    for (uint16_t index = 0; index < total; index++) {
        const uint16_t start = (uint16_t)(index * max_data);
        uint16_t chunk = 0;
        if (len > 0) {
            chunk = (uint16_t)(len - start);
            if (chunk > max_data) {
                chunk = max_data;
            }
        }

        ble_frame_t frame;
        frame.version = BLE_FRAME_VERSION;
        frame.type = frame_type;
        frame.flags = 0;
        frame.sequence = s->seq++;
        frame.length = (uint16_t)(FRAGMENT_HEADER_SIZE + chunk);
        frame.payload = s->frame_buf + BLE_FRAME_HEADER_SIZE;

        /* Fragment 头 (大端) 直接写入帧缓冲 payload 区 */
        uint8_t* p = s->frame_buf + BLE_FRAME_HEADER_SIZE;
        p[0] = (uint8_t)(msg_id >> 8);
        p[1] = (uint8_t)(msg_id & 0xFF);
        p[2] = (uint8_t)(index >> 8);
        p[3] = (uint8_t)(index & 0xFF);
        p[4] = (uint8_t)(total >> 8);
        p[5] = (uint8_t)(total & 0xFF);
        p[6] = (uint8_t)(chunk >> 8);
        p[7] = (uint8_t)(chunk & 0xFF);
        if (chunk > 0 && data != NULL) {
            memcpy(p + FRAGMENT_HEADER_SIZE, data + start, chunk);
        }

        const int out_len =
            ble_frame_encode(&frame, s->frame_buf, sizeof(s->frame_buf));
        if (out_len <= 0) {
            return index; /* 缓冲不足：已发部分 (调用方应检查返回值) */
        }
        send(s->frame_buf, (uint16_t)out_len, ctx);
    }
    return total;
}

/* ---------------- 接收方向 ---------------- */

static int seen_test(const frag_assembly_t* a, uint16_t index)
{
    return (a->seen[index / 32] >> (index % 32)) & 0x1u;
}

static void seen_set(frag_assembly_t* a, uint16_t index)
{
    a->seen[index / 32] |= (uint32_t)1u << (index % 32);
}

void frag_assembler_init(frag_assembler_t* a, uint32_t timeout_ms,
                         void (*on_complete)(uint16_t, uint8_t, const uint8_t*,
                                             uint16_t, void*),
                         void (*on_discard)(uint16_t, const char*, void*),
                         void (*on_duplicate)(uint16_t, void*),
                         void* ctx)
{
    if (a == NULL) {
        return;
    }
    memset(a, 0, sizeof(*a));
    a->timeout_ms = timeout_ms;
    a->on_complete = on_complete;
    a->on_discard = on_discard;
    a->on_duplicate = on_duplicate;
    a->ctx = ctx;
}

void frag_assembler_reset(frag_assembler_t* a)
{
    if (a == NULL) {
        return;
    }
    memset(a->slots, 0, sizeof(a->slots));
    memset(a->completed, 0, sizeof(a->completed));
    a->completed_count = 0;
    a->completed_head = 0;
}

static int is_completed(const frag_assembler_t* a, uint16_t msg_id)
{
    for (uint8_t i = 0; i < a->completed_count; i++) {
        if (a->completed[i] == msg_id) {
            return 1;
        }
    }
    return 0;
}

static void mark_completed(frag_assembler_t* a, uint16_t msg_id)
{
    if (a->completed_count < DEVICE_RX_COMPLETED_CAPACITY) {
        a->completed[(a->completed_head + a->completed_count) %
                     DEVICE_RX_COMPLETED_CAPACITY] = msg_id;
        a->completed_count++;
    } else {
        /* 环形覆盖最旧记录 */
        a->completed[a->completed_head] = msg_id;
        a->completed_head =
            (uint8_t)((a->completed_head + 1) % DEVICE_RX_COMPLETED_CAPACITY);
    }
}

static void unmark_completed(frag_assembler_t* a, uint16_t msg_id)
{
    for (uint8_t i = 0; i < a->completed_count; i++) {
        const uint8_t idx =
            (uint8_t)((a->completed_head + i) % DEVICE_RX_COMPLETED_CAPACITY);
        if (a->completed[idx] == msg_id) {
            /* 简单移除：后续元素前移 */
            for (uint8_t j = i; j + 1 < a->completed_count; j++) {
                const uint8_t cur =
                    (uint8_t)((a->completed_head + j) % DEVICE_RX_COMPLETED_CAPACITY);
                const uint8_t next =
                    (uint8_t)((a->completed_head + j + 1) % DEVICE_RX_COMPLETED_CAPACITY);
                a->completed[cur] = a->completed[next];
            }
            a->completed_count--;
            return;
        }
    }
}

static void discard(frag_assembler_t* a, uint16_t msg_id, const char* reason)
{
    for (uint8_t i = 0; i < DEVICE_RX_ASSEMBLY_SLOTS; i++) {
        if (a->slots[i].in_use && a->slots[i].msg_id == msg_id) {
            a->slots[i].in_use = 0;
        }
    }
    unmark_completed(a, msg_id);
    if (a->on_discard != NULL) {
        a->on_discard(msg_id, reason, a->ctx);
    }
}

void frag_assembler_add(frag_assembler_t* a, const ble_frame_t* frame)
{
    if (a == NULL || frame == NULL) {
        return;
    }
    if (frame->length < FRAGMENT_HEADER_SIZE) {
        if (a->on_discard != NULL) {
            a->on_discard(0xFFFF, "short fragment header", a->ctx);
        }
        return;
    }
    const uint8_t* p = frame->payload;
    const uint16_t msg_id = (uint16_t)(((uint16_t)p[0] << 8) | p[1]);
    const uint16_t index = (uint16_t)(((uint16_t)p[2] << 8) | p[3]);
    const uint16_t total = (uint16_t)(((uint16_t)p[4] << 8) | p[5]);
    const uint16_t length = (uint16_t)(((uint16_t)p[6] << 8) | p[7]);
    const uint8_t* data = p + FRAGMENT_HEADER_SIZE;
    const uint16_t data_len = (uint16_t)(frame->length - FRAGMENT_HEADER_SIZE);

    /* 已组装完成的消息再次到达 (发送端重发) → 通知重发 ACK (§8.5/§7.4) */
    if (is_completed(a, msg_id)) {
        if (a->on_duplicate != NULL) {
            a->on_duplicate(msg_id, a->ctx);
        }
        return;
    }

    if (length != data_len) {
        discard(a, msg_id, "length mismatch");
        return;
    }
    if (total == 0 || total > DEVICE_RX_MAX_FRAGMENTS) {
        discard(a, msg_id, "bad total");
        return;
    }
    if (index >= total) {
        discard(a, msg_id, "index out of range");
        return;
    }

    /* 找/建组装槽 */
    frag_assembly_t* slot = NULL;
    for (uint8_t i = 0; i < DEVICE_RX_ASSEMBLY_SLOTS; i++) {
        if (a->slots[i].in_use && a->slots[i].msg_id == msg_id) {
            slot = &a->slots[i];
            break;
        }
    }
    if (slot == NULL) {
        for (uint8_t i = 0; i < DEVICE_RX_ASSEMBLY_SLOTS; i++) {
            if (!a->slots[i].in_use) {
                slot = &a->slots[i];
                break;
            }
        }
        if (slot == NULL) {
            if (a->on_discard != NULL) {
                a->on_discard(msg_id, "no free assembly slot", a->ctx);
            }
            return;
        }
        memset(slot, 0, sizeof(*slot));
        slot->in_use = 1;
        slot->msg_id = msg_id;
        slot->total = total;
        slot->frame_type = frame->type;
    } else if (slot->total != total) {
        discard(a, msg_id, "total mismatch");
        return;
    } else if (slot->frame_type != frame->type) {
        discard(a, msg_id, "type mismatch");
        return;
    }

    if (seen_test(slot, index)) {
        return; /* 重复分片：忽略 (§8.5) */
    }
    if ((uint32_t)slot->len + length > DEVICE_RX_MESSAGE_MAX) {
        discard(a, msg_id, "message too large");
        return;
    }

    seen_set(slot, index);
    memcpy(slot->data + slot->len, data, length);
    slot->len = (uint16_t)(slot->len + length);
    slot->received++;

    if (slot->received == slot->total) {
        const uint16_t done_len = slot->len;
        const uint8_t done_type = slot->frame_type;
        slot->in_use = 0;
        mark_completed(a, msg_id);
        if (a->on_complete != NULL) {
            a->on_complete(msg_id, done_type, slot->data, done_len, a->ctx);
        }
    }
}

int frag_assembler_tick(frag_assembler_t* a, uint32_t now_ms)
{
    if (a == NULL || a->timeout_ms == 0) {
        return 0;
    }
    int expired = 0;
    for (uint8_t i = 0; i < DEVICE_RX_ASSEMBLY_SLOTS; i++) {
        frag_assembly_t* slot = &a->slots[i];
        if (!slot->in_use) {
            continue;
        }
        if (slot->deadline_ms == 0) {
            slot->deadline_ms = now_ms + a->timeout_ms;
            continue;
        }
        if ((int32_t)(now_ms - slot->deadline_ms) >= 0) {
            const uint16_t msg_id = slot->msg_id;
            slot->in_use = 0;
            unmark_completed(a, msg_id);
            if (a->on_discard != NULL) {
                a->on_discard(msg_id, "assemble timeout", a->ctx);
            }
            expired = 1;
        }
    }
    return expired;
}
