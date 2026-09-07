import 'protocol_messages.dart';

/// 消息编解码抽象 (WORK_V2 §10.6)。
///
/// 第一版使用 [JsonCodec]；正式版可换 CBOR / MessagePack / TLV / 自定义二进制
/// (WORK_V2 §46 迁移策略)，上层无需改动。
///
/// 注意：消息类型由 Frame TYPE 字节区分 (§10.1)，因此 decode 需要
/// [frameType] 入参 —— JSON 体内不携带类型字段。
abstract class MessageCodec {
  /// 编码消息为字节 (不含 Frame 头 / 分片信息)。
  List<int> encode(ProtocolMessage message);

  /// 按帧类型解码字节为消息。
  ProtocolMessage decode(int frameType, List<int> data);
}
