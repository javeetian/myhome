import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/locale_provider.dart';
import '../../providers/theme_provider.dart';

/// 设置页：分栏手风琴布局，每栏标题可点击展开/收起。
///
/// 第一栏 语言：跟随系统 / 简体中文 / English；
/// 第二栏 主题：跟随系统 / 浅色 / 深色。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  /// 语言选项 → 本地化标签。
  String _languageLabel(AppLocalizations l10n, Locale? locale) {
    if (locale == null) {
      return l10n.followSystem;
    }
    switch (locale.languageCode) {
      case 'zh':
        return l10n.languageZh;
      case 'en':
        return l10n.languageEn;
      default:
        return locale.toLanguageTag();
    }
  }

  /// 主题选项 → 本地化标签。
  String _themeLabel(AppLocalizations l10n, ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return l10n.followSystem;
      case ThemeMode.light:
        return l10n.themeLight;
      case ThemeMode.dark:
        return l10n.themeDark;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final locale = ref.watch(localeProvider);
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: ListView(
        children: <Widget>[
          _SettingsSection(
            title: l10n.language,
            children: <Widget>[
              RadioGroup<Locale?>(
                groupValue: locale,
                onChanged: (value) =>
                    ref.read(localeProvider.notifier).setLocale(value),
                child: Column(
                  children: <Widget>[
                    for (final option in languageLocales)
                      RadioListTile<Locale?>(
                        value: option,
                        title: Text(_languageLabel(l10n, option)),
                      ),
                  ],
                ),
              ),
            ],
          ),
          _SettingsSection(
            title: l10n.theme,
            children: <Widget>[
              RadioGroup<ThemeMode>(
                groupValue: themeMode,
                onChanged: (mode) {
                  if (mode != null) {
                    ref.read(themeModeProvider.notifier).setMode(mode);
                  }
                },
                child: Column(
                  children: <Widget>[
                    for (final mode in themeOptions)
                      RadioListTile<ThemeMode>(
                        value: mode,
                        title: Text(_themeLabel(l10n, mode)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 设置分栏：标题 + 展开箭头，点击展开/收起内容。
class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text(title, style: Theme.of(context).textTheme.titleMedium),
      shape: const Border(), // 去掉默认分隔线
      collapsedShape: const Border(),
      children: children,
    );
  }
}
