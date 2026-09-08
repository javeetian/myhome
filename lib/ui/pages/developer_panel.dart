import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/device_session_provider.dart';

/// Developer Mode 调试面板 (WORK_V2 §33)。
///
/// 显示：设备信息、连接状态、协议/固件/UI 版本、能力、
/// 通信统计 (TX/RX/重试/命令延迟分位数)、最近错误。
class DeveloperPanel extends ConsumerWidget {
  const DeveloperPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(deviceSessionProvider);
    final client = session.client;
    final stats = client?.stats;
    final hello = client?.helloAck;

    final rows = <(String, String)>[
      ('设备 ID', session.deviceId ?? '-'),
      ('连接状态', session.phase.name),
      ('协议版本', '${hello?.protocolVersion ?? 1}'),
      ('设备类型', hello?.deviceType.isEmpty ?? true ? '-' : hello!.deviceType),
      ('固件版本', hello?.firmwareVersion.isEmpty ?? true ? '-' : hello!.firmwareVersion),
      ('UI 版本', hello?.uiVersion.isEmpty ?? true ? '-' : hello!.uiVersion),
      ('能力', (hello?.capabilities ?? const <String>[]).join(', ')),
      ('TX 字节', '${stats?.txBytes ?? 0}'),
      ('RX 字节', '${stats?.rxBytes ?? 0}'),
      ('重试次数', '${stats?.retries ?? 0}'),
      ('命令数', '${stats?.commandCount ?? 0}'),
      ('命令延迟 P50', _ms(stats?.commandLatencyP50)),
      ('命令延迟 P95', _ms(stats?.commandLatencyP95)),
      ('命令延迟 P99', _ms(stats?.commandLatencyP99)),
      ('最近错误', session.error ?? '-'),
    ];

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              '开发者模式 (§33)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: <Widget>[
                  for (final (label, value) in rows)
                    ListTile(
                      dense: true,
                      title: Text(label, style: Theme.of(context).textTheme.bodySmall),
                      trailing: Text(
                        value,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _ms(int? value) => value == null ? '-' : '$value ms';
}
