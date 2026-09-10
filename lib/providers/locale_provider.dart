import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 应用语言 (i18n)。
///
/// 状态为 `null` 表示跟随系统语言；用户手动选择后持久化到
/// SharedPreferences，下次启动沿用。可选项见 [languageLocales]。
class LocaleController extends Notifier<Locale?> {
  static const String _prefsKey = 'app_locale';

  @override
  Locale? build() {
    // 启动时异步读取持久化语言，读取完成前先跟随系统。
    unawaited(_loadPersisted());
    return null;
  }

  /// 恢复上次手动选择的语言；读取失败 (如测试环境无插件) 时保持跟随系统。
  Future<void> _loadPersisted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(_prefsKey);
      if (code != null && ref.mounted && state?.toLanguageTag() != code) {
        state = Locale(code);
      }
    } catch (_) {
      // 忽略：跟随系统即可。
    }
  }

  /// 手动选择语言；`null` 恢复跟随系统。
  Future<void> setLocale(Locale? locale) async {
    state = locale;
    final prefs = await SharedPreferences.getInstance();
    if (locale == null) {
      await prefs.remove(_prefsKey);
    } else {
      await prefs.setString(_prefsKey, locale.toLanguageTag());
    }
  }
}

final localeProvider = NotifierProvider<LocaleController, Locale?>(
  LocaleController.new,
);

/// 语言切换选项：跟随系统 / 各支持语言。
/// 与 l10n.yaml 支持的 ARB 文件一一对应，新增语言时在此追加；
/// 选项文案由 UI 层通过 AppLocalizations 解析 (languageSystem/languageZh/…)。
final languageLocales = <Locale?>[null, const Locale('zh'), const Locale('en')];
