import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:myhome/protocol/crc16.dart';

/// CRC-16/CCITT-FALSE 已知答案测试：
/// 固件侧 (ESP32/Arduino) 按相同参数实现后，用同样向量对齐。
void main() {
  test('已知答案: "123456789" → 0x29B1 (CCITT-FALSE)', () {
    expect(
      crc16Ccitt(asciiBytes('123456789')).toRadixString(16).padLeft(4, '0'),
      '29b1',
    );
  });

  test('已知答案: 空数据 → 0xFFFF (初值)', () {
    expect(crc16Ccitt(const <int>[]), 0xFFFF);
  });

  test('已知答案: 单字节 0x00 → 0xE1F0', () {
    expect(crc16Ccitt(const <int>[0x00]), 0xE1F0);
  });

  test('任意单字节翻转必然改变 CRC (错误检测能力)', () {
    final data = List<int>.generate(64, (i) => i * 7 & 0xFF);
    final baseline = crc16Ccitt(data);

    for (var i = 0; i < data.length; i++) {
      final corrupted = List<int>.of(data);
      corrupted[i] ^= 0x01;
      expect(crc16Ccitt(corrupted), isNot(baseline), reason: 'byte $i');
    }
  });

  test('增量计算: 分段结果与整体一致 (流式场景)', () {
    final data = List<int>.generate(100, (i) => i & 0xFF);

    var crc = crc16Ccitt(data.sublist(0, 30));
    crc = crc16Ccitt(data.sublist(30, 70), crc);
    crc = crc16Ccitt(data.sublist(70), crc);

    expect(crc, crc16Ccitt(data));
  });
}

List<int> asciiBytes(String s) => ascii.encode(s);
