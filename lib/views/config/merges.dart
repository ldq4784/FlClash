import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/pages/editor.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MergesView extends ConsumerStatefulWidget {
  const MergesView({super.key});

  @override
  ConsumerState<MergesView> createState() => _MergesViewState();
}

class _MergesViewState extends ConsumerState<MergesView> {
  Future<String?> _showNameDialog({String? initial}) async {
    final appLocalizations = context.appLocalizations;
    final res = await dialogs.showCommonDialog<String>(
      child: InputDialog(
        title: appLocalizations.save,
        value: initial ?? '',
        hintText: '请输入扩展配置名称',
        inputFormatters: TextInputLimits.limit(TextInputLimits.name),
      ),
    );
    return res?.trim().value;
  }

  Future<void> _handleDelete(MergeConfig merge) async {
    final appLocalizations = context.appLocalizations;
    final res = await dialogs.showMessage(
      title: appLocalizations.tip,
      message: TextSpan(
        text: '确定要删除扩展配置「${merge.label}」吗？',
      ),
      destructive: true,
      confirmText: appLocalizations.delete,
    );
    if (res != true) return;
    await mergeManager.delete(merge.id);
    ref.read(setupActionProvider.notifier).applyProfileDebounce(force: true);
  }

  Future<void> _handleToggleGlobal(MergeConfig merge) async {
    await mergeManager.put(merge.copyWith(isGlobal: !merge.isGlobal));
    ref.read(setupActionProvider.notifier).applyProfileDebounce(force: true);
  }

  Future<void> _handleRename(MergeConfig merge) async {
    final res = await _showNameDialog(initial: merge.label);
    if (res == null || res == merge.label) return;
    await mergeManager.put(merge.copyWith(label: res));
  }

  Future<void> _handleSync(MergeConfig merge) async {
    if (merge.url == null) return;
    final appLocalizations = context.appLocalizations;
    final res = await globalState.safeRun(
      () => request.getTextResponseForUrl(merge.url!),
      title: appLocalizations.sync,
    );
    if (res == null || !mounted) return;
    await mergeManager.put(
      merge.copyWith(lastUpdateTime: DateTime.now()),
      res.data ?? '',
    );
    ref.read(setupActionProvider.notifier).applyProfileDebounce(force: true);
    if (mounted) {
      dialogs.showBanner(
        appLocalizations.geoUpdated(merge.label),
        level: BannerLevel.success,
      );
    }
  }

  void _handleToEditor([MergeConfig? merge]) {
    BaseNavigator.push(
      context,
      EditorPage(
        titleEditable: true,
        title: merge?.label ?? '',
        language: Language.yaml,
        schema: EditorSchema.config,
        load: () async {
          if (merge == null) {
            return CodeForgeDocument.fromText(defaultMergeTemplate);
          }
          final path = await appPath.getMergeFilePath(merge.id);
          return openEditorFile(path, ifMissing: defaultMergeTemplate);
        },
        onSave: (ctx, title, content) async {
          var label = title.trim();
          if (label.isEmpty) {
            final res = await _showNameDialog(initial: merge?.label);
            if (res == null) return;
            label = res;
          }
          final text = await content.readText();
          final item = (merge?.copyWith(
            label: label,
            lastUpdateTime: DateTime.now(),
          ) ?? MergeConfig.create(label: label));
          await mergeManager.put(item, text);
          ref.read(setupActionProvider.notifier).applyProfileDebounce(force: true);
          if (ctx.mounted) {
            Navigator.of(ctx).pop();
          }
        },
        onPop: (ctx, title, content) async {
          final res = await dialogs.showSaveChanges();
          if (res == null) return false;
          if (res && ctx.mounted) {
            var label = title.trim();
            if (label.isEmpty) {
              label = merge?.label ?? '未命名配置';
            }
            final text = await content.readText();
            final item = (merge?.copyWith(
              label: label,
              lastUpdateTime: DateTime.now(),
            ) ?? MergeConfig.create(label: label));
            await mergeManager.put(item, text);
            ref.read(setupActionProvider.notifier).applyProfileDebounce(force: true);
          }
          return true;
        },
      ),
    );
  }

  Future<void> _handleImportFromUrl() async {
    final appLocalizations = context.appLocalizations;
    final url = await dialogs.showUrlInput(title: appLocalizations.importUrl);
    if (url == null || !mounted) return;
    final res = await globalState.safeRun(
      () => request.getTextResponseForUrl(url),
      title: appLocalizations.importUrl,
    );
    if (res == null || !mounted) return;
    final fileName =
        Uri.tryParse(
          url,
        )?.pathSegments.lastWhereOrNull((it) => it.isNotEmpty) ??
        '';
    final label = fileName.fileStem.isNotEmpty ? fileName.fileStem : '扩展配置';
    final item = MergeConfig.create(label: label, url: url);
    await mergeManager.put(item, res.data ?? '');
    ref.read(setupActionProvider.notifier).applyProfileDebounce(force: true);
  }

  Future<void> _handleImportFromFile() async {
    final file = await globalState.safeRun(picker.pickerFile);
    if (file == null) return;
    final content = await globalState.safeRun(
      () async => utf8.decode(await file.readBytes()),
    );
    if (content == null || !mounted) return;
    final label = file.name.fileStem.isNotEmpty ? file.name.fileStem : '扩展配置';
    final item = MergeConfig.create(label: label);
    await mergeManager.put(item, content);
    ref.read(setupActionProvider.notifier).applyProfileDebounce(force: true);
  }

  List<PopupMenuItem> _buildMenuItems(MergeConfig merge) {
    final appLocalizations = context.appLocalizations;
    return [
      PopupMenuItem(
        glyph: AppGlyphs.edit,
        label: appLocalizations.edit,
        onPressed: () => _handleToEditor(merge),
      ),
      PopupMenuItem(
        glyph: AppGlyphs.textShort,
        label: appLocalizations.rename,
        onPressed: () => _handleRename(merge),
      ),
      PopupMenuItem(
        glyph: merge.isGlobal ? AppGlyphs.puzzle : AppGlyphs.sparkle,
        label: merge.isGlobal ? '设为单订阅模式' : '设为全局生效',
        onPressed: () => _handleToggleGlobal(merge),
      ),
      if (merge.url != null)
        PopupMenuItem(
          glyph: AppGlyphs.sync,
          label: appLocalizations.sync,
          onPressed: () => _handleSync(merge),
        ),
      PopupMenuItem(
        danger: true,
        glyph: AppGlyphs.delete,
        label: appLocalizations.delete,
        onPressed: () => _handleDelete(merge),
      ),
    ];
  }

  Widget _buildItem(List<MergeConfig> merges, int index) {
    final merge = merges[index];
    final subtitleText = merge.isGlobal
        ? '全局生效 (所有订阅自动应用)'
        : (merge.url != null ? '远程配置' : '本地配置');
    return SortableItem(
      key: ValueKey(merge.id),
      index: index,
      child: ContextMenuRegion(
        menuItems: _buildMenuItems(merge),
        child: ItemPositionProvider(
          position: ItemPosition.get(index, merges.length),
          child: DecorationListItem(
            contentPadding: const EdgeInsets.only(left: 16),
            leading: GlyphIcon(
              merge.isGlobal ? AppGlyphs.puzzle : AppGlyphs.edit,
            ),
            title: Text(
              merge.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              subtitleText,
              style: context.listCaptionStyle,
            ),
            trailing: Padding(
              padding: const EdgeInsetsDirectional.only(end: 16),
              child: LastUpdateTimeText(
                lastUpdateDate: merge.lastUpdateTime,
                compact: true,
                style: context.listCaptionStyle,
              ),
            ),
            onPressed: () => _handleToEditor(merge),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(List<MergeConfig> merges) {
    return NullStatusSwitcher(
      isEmpty: merges.isEmpty,
      nullStatus: const NullStatus(
        illustration: NullStatusIllustration.rules,
        label: '暂无扩展配置',
      ),
      child: PrismReorderableListView(
        padding: const EdgeInsets.all(16).copyWith(
          top: context.contentTopPadding,
          bottom: 16 + context.bottomInset,
        ),
        itemCount: merges.length,
        itemBuilder: (_, index) => _buildItem(merges, index),
        proxyDecorator: (_, index, animation) {
          return commonProxyDecorator(
            _buildItem(merges, index),
            index,
            animation,
          );
        },
        onReorderItem: mergeManager.reorder,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return ListenableBuilder(
      listenable: mergeManager.changeNotifier,
      builder: (context, _) {
        return FutureBuilder<List<MergeConfig>>(
          future: mergeManager.getAll(),
          builder: (context, snapshot) {
            final merges = snapshot.data ?? [];
            return Scaffold(
              canSort: merges.length > 1,
              actions: [
                PopupAnchor(
                  targetBuilder: (open) {
                    return IconButton(
                      tooltip: appLocalizations.add,
                      onPressed: open,
                      icon: const GlyphIcon(AppGlyphs.addCircle),
                    );
                  },
                  popupBuilder: (_) => PopupMenu(
                    items: [
                      PopupMenuItem(
                        glyph: AppGlyphs.compose,
                        label: appLocalizations.startFromScratch,
                        onPressed: _handleToEditor,
                      ),
                      PopupMenuItem(
                        glyph: AppGlyphs.cloudDownload,
                        label: appLocalizations.importUrl,
                        onPressed: _handleImportFromUrl,
                      ),
                      PopupMenuItem(
                        glyph: AppGlyphs.importFile,
                        label: appLocalizations.importFile,
                        onPressed: _handleImportFromFile,
                      ),
                    ],
                  ),
                ),
              ],
              body: _buildContent(merges),
              title: '扩展配置',
            );
          },
        );
      },
    );
  }
}
