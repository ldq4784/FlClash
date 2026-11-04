import 'dart:async';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/pages/editor.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class EnhanceTile extends ConsumerStatefulWidget {
  final String title;
  final String description;
  final Future<String> Function() pathResolver;
  final String template;
  final Language language;
  final EditorSchema schema;
  final Glyph icon;
  final VoidCallback? onModified;

  const EnhanceTile({
    super.key,
    required this.title,
    required this.description,
    required this.pathResolver,
    required this.template,
    required this.language,
    this.schema = EditorSchema.config,
    required this.icon,
    this.onModified,
  });

  @override
  ConsumerState<EnhanceTile> createState() => _EnhanceTileState();
}

class _EnhanceTileState extends ConsumerState<EnhanceTile> {
  String? _resolvedPath;
  bool _isActive = false;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final path = await widget.pathResolver();
    final file = File(path);
    var active = false;
    if (await file.exists()) {
      final content = await file.readAsString();
      active = widget.language == Language.javaScript
          ? isNonEmptyScript(content)
          : isNonEmptyYaml(content);
    }
    if (mounted) {
      setState(() {
        _resolvedPath = path;
        _isActive = active;
      });
    }
  }

  Future<void> _openEditor() async {
    final path = _resolvedPath ?? await widget.pathResolver();
    if (!mounted) return;
    await BaseNavigator.push(
      context,
      EditorPage(
        title: widget.title,
        language: widget.language,
        schema: widget.schema,
        load: () async {
          final file = File(path);
          if (!await file.exists()) {
            return CodeForgeDocument.fromText(widget.template);
          }
          return openEditorFile(path, ifMissing: widget.template);
        },
        onSave: (ctx, _, content) async {
          final text = await content.readText();
          final file = File(path);
          await file.parent.create(recursive: true);
          await file.writeAsString(text);
          if (ctx.mounted) {
            Navigator.of(ctx).pop();
          }
        },
        onPop: (ctx, _, content) async {
          final res = await dialogs.showSaveChanges();
          if (res == null) return false;
          if (res && ctx.mounted) {
            final text = await content.readText();
            final file = File(path);
            await file.parent.create(recursive: true);
            await file.writeAsString(text);
          }
          return true;
        },
      ),
    );
    ref.read(setupActionProvider.notifier).applyProfileDebounce(force: true);
    widget.onModified?.call();
    await _loadState();
  }

  Future<void> _handleReset() async {
    final path = _resolvedPath ?? await widget.pathResolver();
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(widget.template);
    ref.read(setupActionProvider.notifier).applyProfileDebounce(force: true);
    widget.onModified?.call();
    await _loadState();
  }

  Future<void> _handleClear() async {
    final path = _resolvedPath ?? await widget.pathResolver();
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
    ref.read(setupActionProvider.notifier).applyProfileDebounce(force: true);
    widget.onModified?.call();
    await _loadState();
  }

  @override
  Widget build(BuildContext context) {
    final statusText = _isActive ? '已启用' : '未配置';
    return ContextMenuRegion(
      menuItems: [
        CommonPopupMenuItem(
          glyph: AppGlyphs.edit,
          label: '编辑',
          onPressed: _openEditor,
        ),
        CommonPopupMenuItem(
          glyph: AppGlyphs.reset,
          label: '重置为模板',
          onPressed: _handleReset,
        ),
        if (_isActive)
          CommonPopupMenuItem(
            danger: true,
            glyph: AppGlyphs.delete,
            label: '清除配置',
            onPressed: _handleClear,
          ),
      ],
      child: DecorationListItem(
        title: Text(widget.title),
        subtitle: Text('${widget.description} · $statusText'),
        leading: GlyphIcon(widget.icon),
        trailing: const GlyphIcon(AppGlyphs.chevronForward),
        onPressed: _openEditor,
      ),
    );
  }
}

class GlobalEnhanceView extends StatelessWidget {
  const GlobalEnhanceView({super.key});

  @override
  Widget build(BuildContext context) {
    return BaseScaffold(
      title: '全局扩展覆写',
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(
          top: context.sectionsTopPadding,
          bottom: 16 + context.bottomInset,
        ),
        children: [
          generateSection(
            title: '全局扩展配置与脚本 (Clash Verge Rev 兼容)',
            items: [
              EnhanceTile(
                title: '全局扩展配置 (Global Merge)',
                description: 'YAML 深度合并，对所有订阅生效',
                pathResolver: () => appPath.globalMergePath,
                template: globalMergeTemplate,
                language: Language.yaml,
                schema: EditorSchema.config,
                icon: AppGlyphs.puzzle,
              ),
              EnhanceTile(
                title: '全局扩展脚本 (Global Script)',
                description: 'JavaScript 脚本，对所有订阅生效',
                pathResolver: () => appPath.globalScriptPath,
                template: globalScriptTemplate,
                language: Language.javaScript,
                icon: AppGlyphs.code,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
