import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 历史设备条目：曾成功连接过的设备 (主界面卡片列表数据)。
class DeviceHistoryEntry {
  const DeviceHistoryEntry({
    required this.id,
    required this.name,
    required this.kind,
    required this.addedAt,
  });

  /// 设备 id (重连凭据)。
  final String id;

  /// 展示名称 (广播名；demo 为模板名)。
  final String name;

  /// 连接方式：真实 BLE 设备或内置演示设备。
  final DeviceHistoryKind kind;

  /// 最近一次连接时间 (排序与卡片副标题用)。
  final DateTime addedAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'kind': kind.name,
        'addedAt': addedAt.toIso8601String(),
      };

  factory DeviceHistoryEntry.fromJson(Map<String, dynamic> json) =>
      DeviceHistoryEntry(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        kind: DeviceHistoryKind.values.asNameMap()[json['kind']] ??
            DeviceHistoryKind.ble,
        addedAt: DateTime.tryParse(json['addedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

/// 设备连接方式。
enum DeviceHistoryKind { ble, demo }

/// 历史设备列表：持久化到 SharedPreferences，最近连接在前。
class DeviceHistoryController extends Notifier<List<DeviceHistoryEntry>> {
  static const String _prefsKey = 'device_history';

  @override
  List<DeviceHistoryEntry> build() {
    unawaited(_load());
    return const <DeviceHistoryEntry>[];
  }

  /// 恢复持久化的历史列表；读取失败 (如测试环境无插件) 时保持空列表。
  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || !ref.mounted) {
        return;
      }
      final list = (jsonDecode(raw) as List<dynamic>)
          .map((e) => DeviceHistoryEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      state = list;
    } catch (_) {
      // 忽略：空列表即可。
    }
  }

  /// 记录一次成功连接：同 id 已存在则更新名称与时间并移到最前。
  Future<void> add(String id, String name, DeviceHistoryKind kind) async {
    final entry = DeviceHistoryEntry(
      id: id,
      name: name,
      kind: kind,
      addedAt: DateTime.now(),
    );
    state = <DeviceHistoryEntry>[entry, ...state.where((e) => e.id != id)];
    await _persist();
  }

  /// 从历史移除条目。
  Future<void> remove(String id) async {
    state = state.where((e) => e.id != id).toList();
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode(state.map((e) => e.toJson()).toList()),
      );
    } catch (_) {
      // 持久化失败不影响本次会话内展示。
    }
  }
}

final deviceHistoryProvider =
    NotifierProvider<DeviceHistoryController, List<DeviceHistoryEntry>>(
  DeviceHistoryController.new,
);
