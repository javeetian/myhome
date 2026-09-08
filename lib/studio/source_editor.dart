import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart' show atomOneLightTheme;
import 'package:highlight/highlight.dart' show Mode;
import 'package:highlight/languages/cpp.dart' show cpp;
import 'package:highlight/languages/css.dart' show css;
import 'package:highlight/languages/dart.dart' show dart;
import 'package:highlight/languages/xml.dart' show xml; // highlight 将 HTML 归入 xml
import 'package:highlight/languages/javascript.dart' show javascript;
import 'package:highlight/languages/json.dart' show json;
import 'package:highlight/languages/plaintext.dart' show plaintext;
import 'package:highlight/languages/yaml.dart' show yaml;
import 'package:path/path.dart' as p;

/// 源码编辑器 (WORK_V3 §30 扩展)：语法高亮 + 行号 + 防抖自动保存。
///
/// 保存写入文件后，Studio 的 UI Watch (Phase 37) 自动重打包并重载
/// WebView 预览，实现"改源码立刻显示结果"。二进制文件显示占位提示。
class SourceEditor extends StatefulWidget {
  const SourceEditor({super.key, required this.path});

  final String path;

  @override
  State<SourceEditor> createState() => _SourceEditorState();
}

class _SourceEditorState extends State<SourceEditor> {
  late final CodeController _controller;
  Timer? _debounce;
  bool _dirty = false;
  bool _binary = false;

  @override
  void initState() {
    super.initState();
    try {
      final text = utf8.decode(File(widget.path).readAsBytesSync());
      _controller = CodeController(text: text, language: _language(widget.path));
    } on FormatException {
      _binary = true; // 非 UTF-8 → 二进制文件
      _controller = CodeController();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    // 关闭标签/切换前把未保存内容落盘
    if (_dirty && !_binary) {
      _writeFile();
    }
    _controller.dispose();
    super.dispose();
  }

  /// 按扩展名选择高亮语言。
  Mode _language(String path) {
    if (path.endsWith('.html')) return xml;
    if (path.endsWith('.css')) return css;
    if (path.endsWith('.js')) return javascript;
    if (path.endsWith('.dart')) return dart;
    if (path.endsWith('.json')) return json;
    if (path.endsWith('.yaml') || path.endsWith('.yml')) return yaml;
    if (path.endsWith('.c') || path.endsWith('.h')) return cpp;
    return plaintext;
  }

  void _onChanged(String _) {
    setState(() => _dirty = true);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _save);
  }

  void _save() {
    _debounce?.cancel();
    if (!_dirty || _binary) {
      return;
    }
    _writeFile();
    if (mounted) {
      setState(() => _dirty = false);
    }
  }

  void _writeFile() => File(widget.path).writeAsStringSync(_controller.text);

  @override
  Widget build(BuildContext context) {
    if (_binary) {
      return Center(
        child: Text(
          '二进制文件不可编辑\n${p.basename(widget.path)}',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 2, 4, 2),
          child: Row(
            children: <Widget>[
              Icon(
                Icons.circle,
                size: 8,
                color: _dirty ? Colors.orange : Colors.transparent,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  widget.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.save_outlined, size: 16),
                tooltip: '保存 (Cmd/Ctrl+S)',
                visualDensity: VisualDensity.compact,
                onPressed: _dirty ? _save : null,
              ),
            ],
          ),
        ),
        Expanded(
          child: Shortcuts(
            shortcuts: <ShortcutActivator, Intent>{
              SingleActivator(LogicalKeyboardKey.keyS, meta: true):
                  const _SaveIntent(),
              SingleActivator(LogicalKeyboardKey.keyS, control: true):
                  const _SaveIntent(),
            },
            child: Actions(
              actions: <Type, Action<Intent>>{
                _SaveIntent: CallbackAction<_SaveIntent>(
                  onInvoke: (_) {
                    _save();
                    return null;
                  },
                ),
              },
              child: CodeTheme(
                data: CodeThemeData(styles: atomOneLightTheme),
                child: CodeField(
                  controller: _controller,
                  expands: true,
                  onChanged: _onChanged,
                  textStyle: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.5,
                  ),
                  padding: const EdgeInsets.all(12),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SaveIntent extends Intent {
  const _SaveIntent();
}
