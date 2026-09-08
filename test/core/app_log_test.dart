import 'package:flutter_test/flutter_test.dart';

import 'package:myhome/core/app_log.dart';

/// 统一日志系统 (WORK_V2 §31/§32) 测试。
void main() {
  group('AppLog 格式 (§31)', () {
    test('输出含时间/等级/模块/上下文前缀', () {
      final lines = <String>[];
      final log = AppLog(output: lines.add);

      log.info('BLE', 'write 32 bytes', deviceId: 'abc', seq: 100);

      expect(lines.single, matches(
        r'^\d{2}:\d{2}:\d{2}\.\d{3} INFO BLE device=abc seq=100 write 32 bytes$',
      ));
    });

    test('request_id 前缀', () {
      final lines = <String>[];
      final log = AppLog(output: lines.add);

      log.debug('DEVICE', 'cmd=led_on', requestId: 42);

      expect(lines.single, contains('request_id=42'));
      expect(lines.single, contains('cmd=led_on'));
    });

    test('无上下文时只有基础前缀', () {
      final lines = <String>[];
      final log = AppLog(output: lines.add);

      log.warn('UI', 'hello');

      expect(lines.single, matches(r'^\d{2}:\d{2}:\d{2}\.\d{3} WARN UI hello$'));
    });
  });

  group('等级过滤 (§32)', () {
    test('低于当前等级的日志被过滤', () {
      final lines = <String>[];
      final log = AppLog(level: LogLevel.warn, output: lines.add);

      log.trace('A', 't');
      log.debug('A', 'd');
      log.info('A', 'i');
      log.warn('A', 'w');
      log.error('A', 'e');

      expect(lines, hasLength(2));
      expect(lines[0], contains('WARN'));
      expect(lines[1], contains('ERROR'));
    });

    test('等级可运行时调整', () {
      final lines = <String>[];
      final log = AppLog(level: LogLevel.error, output: lines.add);

      log.info('A', 'x');
      expect(lines, isEmpty);

      log.level = LogLevel.debug;
      log.debug('A', 'y');
      expect(lines, hasLength(1));
      expect(lines.single, contains('DEBUG'));
    });
  });
}
