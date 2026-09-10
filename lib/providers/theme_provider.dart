import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 应用主题模式：跟随系统 / 浅色 / 深色。
/// 手动选择后持久化到 SharedPreferences，下次启动沿用。
class ThemeModeController extends Notifier<ThemeMode> {
  static const String _prefsKey = 'app_theme_mode';

  @override
  ThemeMode build() {
    unawaited(_loadPersisted());
    return ThemeMode.system;
  }

  /// 恢复持久化的主题模式；读取失败 (如测试环境无插件) 时保持跟随系统。
  Future<void> _loadPersisted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || !ref.mounted) {
        return;
      }
      state = ThemeMode.values.asNameMap()[raw] ?? ThemeMode.system;
    } catch (_) {
      // 忽略：跟随系统即可。
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, mode.name);
    } catch (_) {
      // 持久化失败不影响本次会话内生效。
    }
  }
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

/// 主题选项列表；选项文案由 UI 层通过 AppLocalizations 解析
/// (followSystem/themeLight/themeDark)。
final themeOptions = <ThemeMode>[
  ThemeMode.system,
  ThemeMode.light,
  ThemeMode.dark,
];
