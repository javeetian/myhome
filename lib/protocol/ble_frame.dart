import 'crc16.dart';

/// 帧解析/校验异常 (WORK_V2 §7.3：校验失败 → 丢弃，Phase 4 再引入 NACK)。
class FrameException implements Exception {
  const FrameException(this.message);

  final String message;

  @override
  String toString() => 'FrameException: $message';
}

/// 帧 TYPE 合法值 (WORK_V2 §7.5「非法 Type」校验 / §10.1 注册表)。
///
/// 当前注册：
///   0x01-0x05  业务帧 (§10.1 COMMAND/RESPONSE/EVENT/STATE/PATCH)
///   0x10/0x11  ACK / NACK (§9.1)
///   0x20-0x23  HELLO / HELLO_ACK / PING / PONG (§15.3 UI 下载流程)
///   0x30/0x31  RESOURCE_REQUEST / RESOURCE_RESPONSE (§27 Resource 流程)
class FrameType {
  FrameType._();

  static const int command = 0x01;
  static const int response = 0x02;
  static const int event = 0x03;
  static const int state = 0x04;
  static const int patch = 0x05;
  static const int ack = 0x10;
  static const int nack = 0x11;
  static const int hello = 0x20;
  static const int helloAck = 0x21;
  static const int ping = 0x22;
  static const int pong = 0x23;
  static const int resourceRequest = 0x30;
  static const int resourceResponse = 0x31;

  /// 全量状态请求 (WORK_V2 §16.5/§16.6 STATE_REQUEST)。
  /// §10.1 注册表扩展，固件侧需对齐。
  static const int stateRequest = 0x32;

  static const Set<int> valid = <int>{
    command,
    response,
    event,
    state,
    patch,
    ack,
    nack,
    hello,
    helloAck,
    ping,
    pong,
    resourceRequest,
    resourceResponse,
    stateRequest,
  };

  static bool isValid(int type) => valid.contains(type);
}

/// BLE 传输帧 (WORK_V2 §7)。
///
/// 字节布局 (大端)：
/// ```text
/// ┌──────┬──────┬───────┬────────┬────────┬─────────────┬────────┐
/// │ VER  │ TYPE │ FLAGS │  SEQ   │ LENGTH │   PAYLOAD   │ CRC16  │
/// │ 1B   │ 1B   │ 1B    │ 2B     │ 2B     │   N bytes   │ 2B     │
/// └──────┴──────┴───────┴────────┴────────┴─────────────┴────────┘
/// └──────────── CRC 覆盖范围 ──────────────────┘
/// ```
///
/// SEQ 归 Transport 层使用 (ACK/去重/重传/排序)，不得作为业务 Request ID (§7.4)。
class BleFrame {
  BleFrame({
    required this.version,
    required this.type,
    required this.flags,
    required this.sequence,
    required List<int> payload,
  }) : payload = List<int>.unmodifiable(payload);

  /// 当前帧协议版本。
  static const int currentVersion = 1;

  /// 头部长度：VER+TYPE+FLAGS+SEQ+LENGTH。
  static const int headerSize = 7;

  /// CRC 字段长度。
  static const int crcSize = 2;

  /// PAYLOAD 上限 (LENGTH 2 字节)。
  static const int maxPayloadSize = 0xFFFF;

  final int version;
  final int type;
  final int flags;
  final int sequence;
  final List<int> payload;

  /// 编码前的字段合法性校验。
  void validate() {
    if (version != currentVersion) {
      throw FrameException('Version 错误: $version (当前 $currentVersion)');
    }
    if (!FrameType.isValid(type)) {
      throw FrameException('非法 Type: 0x${type.toRadixString(16)}');
    }
    if (flags < 0 || flags > 0xFF) {
      throw FrameException('非法 FLAGS: $flags');
    }
    if (sequence < 0 || sequence > 0xFFFF) {
      throw FrameException('非法 SEQ: $sequence');
    }
    if (payload.length > maxPayloadSize) {
      throw FrameException('Payload 超限: ${payload.length} > $maxPayloadSize');
    }
  }

  /// 编码：Header + Payload + CRC16 (大端)。
  List<int> encode() {
    validate();
    final bytes = <int>[
      version & 0xFF,
      type & 0xFF,
      flags & 0xFF,
      (sequence >> 8) & 0xFF,
      sequence & 0xFF,
      (payload.length >> 8) & 0xFF,
      payload.length & 0xFF,
      ...payload,
    ];
    final crc = crc16Ccitt(bytes);
    bytes
      ..add((crc >> 8) & 0xFF)
      ..add(crc & 0xFF);
    return bytes;
  }

  /// 解码：要求 [bytes] 恰好为一帧 (Header + Payload + CRC)。
  ///
  /// 字节流粘包/半包由 Phase 3 Assembler 处理，本方法只做严格定长解码。
  /// 失败抛 [FrameException] (调用方丢弃该帧，§7.3)。
  static BleFrame decode(List<int> bytes) {
    if (bytes.length < headerSize) {
      throw FrameException('长度不足: ${bytes.length} < $headerSize');
    }
    final version = bytes[0];
    final type = bytes[1];
    final flags = bytes[2];
    final sequence = (bytes[3] << 8) | bytes[4];
    final length = (bytes[5] << 8) | bytes[6];

    final expected = headerSize + length + crcSize;
    if (bytes.length != expected) {
      throw FrameException(
        'Length 错误: LENGTH=$length 期望 $expected 字节, 实际 ${bytes.length}',
      );
    }

    final payload = bytes.sublist(headerSize, headerSize + length);

    // CRC 校验 (覆盖 Header + Payload)
    final expectedCrc = (bytes[expected - 2] << 8) | bytes[expected - 1];
    final actualCrc = crc16Ccitt(bytes.sublist(0, expected - crcSize));
    if (actualCrc != expectedCrc) {
      throw FrameException(
        'CRC 错误: 期望 0x${expectedCrc.toRadixString(16).padLeft(4, '0')}, '
        '实际 0x${actualCrc.toRadixString(16).padLeft(4, '0')}',
      );
    }

    return BleFrame(
      version: version,
      type: type,
      flags: flags,
      sequence: sequence,
      payload: payload,
    )..validate();
  }
}
