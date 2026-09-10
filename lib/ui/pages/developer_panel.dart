import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/device_session_provider.dart';
import '../connection_phase_l10n.dart';

/// Developer Mode 调试面板 (WORK_V2 §33)。
///
/// 显示：设备信息、连接状态、协议/固件/UI 版本、能力、
/// 通信统计 (TX/RX/重试/命令延迟分位数)、最近错误。
class DeveloperPanel extends ConsumerWidget {
  const DeveloperPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final session = ref.watch(deviceSessionProvider);
    final client = session.client;
    final stats = client?.stats;
    final hello = client?.helloAck;

    final rows = <(String, String)>[
      (l10n.devDeviceId, session.deviceId ?? '-'),
      (l10n.devConnectionState, session.phase.label(l10n)),
      (l10n.devProtocolVersion, '${hello?.protocolVersion ?? 1}'),
      (l10n.devDeviceType, hello?.deviceType.isEmpty ?? true ? '-' : hello!.deviceType),
      (l10n.devFirmwareVersion, hello?.firmwareVersion.isEmpty ?? true ? '-' : hello!.firmwareVersion),
      (l10n.devUiVersion, hello?.uiVersion.isEmpty ?? true ? '-' : hello!.uiVersion),
      (l10n.devCapabilities, (hello?.capabilities ?? const <String>[]).join(', ')),
      (l10n.devTxBytes, '${stats?.txBytes ?? 0}'),
      (l10n.devRxBytes, '${stats?.rxBytes ?? 0}'),
      (l10n.devRetries, '${stats?.retries ?? 0}'),
      (l10n.devCommandCount, '${stats?.commandCount ?? 0}'),
      (l10n.devLatencyP50, _ms(stats?.commandLatencyP50)),
      (l10n.devLatencyP95, _ms(stats?.commandLatencyP95)),
      (l10n.devLatencyP99, _ms(stats?.commandLatencyP99)),
      (l10n.devLastError, session.error ?? '-'),
    ];

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              l10n.devPanelTitle,
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
