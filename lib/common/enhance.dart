import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:fl_clash/common/common.dart';
import 'package:flutter/foundation.dart';

const defaultMergeTemplate = '''# 扩展配置 (Merge Template)
# 支持常规 YAML 属性覆盖，以及特殊的前置/后置插入字段:
#   prepend-rules: 前置规则列表 (插入到现有 rules 最前面)
#   append-rules: 后置规则列表 (插入到现有 rules 最后面)
#   prepend-proxies: 前置节点列表
#   append-proxies: 后置节点列表
#   prepend-proxy-groups: 前置策略组列表
#   append-proxy-groups: 后置策略组列表

# prepend-rules:
#   - DOMAIN-SUFFIX,google.com,DIRECT
#   - IP-CIDR,127.0.0.0/8,DIRECT
''';

class MergeConfig {
  final String id;
  final String label;
  final DateTime lastUpdateTime;
  final String? url;
  final bool isGlobal;

  const MergeConfig({
    required this.id,
    required this.label,
    required this.lastUpdateTime,
    this.url,
    this.isGlobal = false,
  });

  MergeConfig copyWith({
    String? label,
    DateTime? lastUpdateTime,
    String? url,
    bool? isGlobal,
  }) {
    return MergeConfig(
      id: id,
      label: label ?? this.label,
      lastUpdateTime: lastUpdateTime ?? this.lastUpdateTime,
      url: url ?? this.url,
      isGlobal: isGlobal ?? this.isGlobal,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'lastUpdateTime': lastUpdateTime.toIso8601String(),
    if (url != null) 'url': url,
    if (isGlobal) 'isGlobal': true,
  };

  factory MergeConfig.fromJson(Map<String, dynamic> json) => MergeConfig(
    id: json['id'] as String? ?? snowflake.id.toString(),
    label: json['label'] as String? ?? '未命名',
    lastUpdateTime:
        DateTime.tryParse(json['lastUpdateTime'] as String? ?? '') ??
        DateTime.now(),
    url: json['url'] as String?,
    isGlobal: json['isGlobal'] as bool? ?? false,
  );

  factory MergeConfig.create({
    required String label,
    String? url,
    bool isGlobal = false,
  }) {
    return MergeConfig(
      id: snowflake.id.toString(),
      label: label,
      lastUpdateTime: DateTime.now(),
      url: url,
      isGlobal: isGlobal,
    );
  }
}

class MergeManager {
  static final MergeManager instance = MergeManager._();
  MergeManager._();

  final ValueNotifier<int> changeNotifier = ValueNotifier<int>(0);
  List<MergeConfig>? _cache;
  final Map<int, List<String>> _selectedCache = {};

  void _notify() {
    changeNotifier.value++;
  }

  Future<List<MergeConfig>> getAll() async {
    if (_cache != null) return _cache!;
    final configFile = File(await appPath.mergesConfigPath);
    if (!await configFile.exists()) {
      _cache = [];
      return _cache!;
    }
    try {
      final text = await configFile.readAsString();
      final list = json.decode(text) as List<dynamic>;
      _cache = list
          .whereType<Map<String, dynamic>>()
          .map(MergeConfig.fromJson)
          .toList();
    } catch (_) {
      _cache = [];
    }
    return _cache!;
  }

  Future<void> saveAll(List<MergeConfig> items) async {
    _cache = List.from(items);
    final configFile = File(await appPath.mergesConfigPath);
    await configFile.parent.create(recursive: true);
    final jsonStr = json.encode(items.map((e) => e.toJson()).toList());
    await configFile.writeAsString(jsonStr);
    _notify();
  }

  Future<void> put(MergeConfig item, [String? content]) async {
    final list = await getAll();
    final index = list.indexWhere((e) => e.id == item.id);
    if (index >= 0) {
      list[index] = item;
    } else {
      list.add(item);
    }
    if (content != null) {
      final file = File(await appPath.getMergeFilePath(item.id));
      await file.parent.create(recursive: true);
      await file.writeAsString(content);
    }
    await saveAll(list);
  }

  Future<void> delete(String id) async {
    final list = await getAll();
    list.removeWhere((e) => e.id == id);
    final file = File(await appPath.getMergeFilePath(id));
    if (await file.exists()) {
      await file.delete();
    }
    await saveAll(list);
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    final list = await getAll();
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    await saveAll(list);
  }

  Future<String> getContent(String id) async {
    final file = File(await appPath.getMergeFilePath(id));
    if (!await file.exists()) return '';
    return file.readAsString();
  }

  Future<List<String>> getSelectedIds(int profileId) async {
    if (_selectedCache.containsKey(profileId)) {
      return _selectedCache[profileId]!;
    }
    final file = File(await appPath.getProfileSelectedMergesPath(profileId));
    if (!await file.exists()) {
      _selectedCache[profileId] = [];
      return [];
    }
    try {
      final text = await file.readAsString();
      final list = (json.decode(text) as List).cast<String>();
      _selectedCache[profileId] = list;
      return list;
    } catch (_) {
      _selectedCache[profileId] = [];
      return [];
    }
  }

  Future<void> saveSelectedIds(int profileId, List<String> ids) async {
    _selectedCache[profileId] = List.from(ids);
    final file = File(await appPath.getProfileSelectedMergesPath(profileId));
    await file.parent.create(recursive: true);
    await file.writeAsString(json.encode(ids));
    _notify();
  }

  Future<void> toggleSelected(int profileId, String id) async {
    final current = await getSelectedIds(profileId);
    final next = List<String>.from(current);
    if (next.contains(id)) {
      next.remove(id);
    } else {
      next.add(id);
    }
    await saveSelectedIds(profileId, next);
  }
}

final mergeManager = MergeManager.instance;

Map<String, dynamic> applyMerge(
  Map<String, dynamic> config,
  Map<String, dynamic> merge,
) {
  final result = Map<String, dynamic>.from(config);
  final mergeClean = Map<String, dynamic>.from(merge);

  final prependRules = (mergeClean.remove('prepend-rules') as List?)?.toList();
  final appendRules = (mergeClean.remove('append-rules') as List?)?.toList();
  final prependProxies =
      (mergeClean.remove('prepend-proxies') as List?)?.toList();
  final appendProxies =
      (mergeClean.remove('append-proxies') as List?)?.toList();
  final prependGroups =
      (mergeClean.remove('prepend-proxy-groups') as List?)?.toList();
  final appendGroups =
      (mergeClean.remove('append-proxy-groups') as List?)?.toList();

  _deepMergeMap(result, mergeClean);

  if (prependRules != null || appendRules != null) {
    final currentRules = (result['rules'] as List?)?.toList() ?? <dynamic>[];
    result['rules'] = [
      if (prependRules != null) ...prependRules,
      ...currentRules,
      if (appendRules != null) ...appendRules,
    ];
  }

  if (prependProxies != null || appendProxies != null) {
    final currentProxies =
        (result['proxies'] as List?)?.toList() ?? <dynamic>[];
    result['proxies'] = [
      if (prependProxies != null) ...prependProxies,
      ...currentProxies,
      if (appendProxies != null) ...appendProxies,
    ];
  }

  if (prependGroups != null || appendGroups != null) {
    final currentGroups =
        (result['proxy-groups'] as List?)?.toList() ?? <dynamic>[];
    result['proxy-groups'] = [
      if (prependGroups != null) ...prependGroups,
      ...currentGroups,
      if (appendGroups != null) ...appendGroups,
    ];
  }

  return result;
}

void _deepMergeMap(
  Map<String, dynamic> target,
  Map<dynamic, dynamic> source,
) {
  for (final entry in source.entries) {
    final key = entry.key.toString();
    final value = entry.value;
    if (value is Map) {
      final targetVal = target[key];
      if (targetVal is Map<String, dynamic>) {
        _deepMergeMap(targetVal, value);
      } else if (targetVal is Map) {
        final converted = Map<String, dynamic>.from(targetVal);
        target[key] = converted;
        _deepMergeMap(converted, value);
      } else {
        target[key] = _deepConvert(value);
      }
    } else if (value is List) {
      target[key] = _deepConvert(value);
    } else {
      target[key] = value;
    }
  }
}

dynamic _deepConvert(dynamic value) {
  if (value is Map) {
    return value.map((k, v) => MapEntry(k.toString(), _deepConvert(v)));
  }
  if (value is List) {
    return value.map(_deepConvert).toList();
  }
  return value;
}

bool isNonEmptyYaml(String? content) {
  if (content == null || content.trim().isEmpty) return false;
  try {
    final loaded = loadPlainYaml(content);
    if (loaded is Map && loaded.isNotEmpty) return true;
    if (loaded is List && loaded.isNotEmpty) return true;
  } catch (_) {
    return content.trim().isNotEmpty;
  }
  return false;
}

bool isNonEmptyScript(String? content) {
  if (content == null) return false;
  final trimmed = content.trim();
  if (trimmed.isEmpty) return false;
  final stripped = trimmed
      .replaceAll(RegExp(r'//.*'), '')
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
      .replaceAll(RegExp(r'\s+'), '');
  if (stripped == 'functionmain(config){returnconfig;}' ||
      stripped == 'constmain=(config)=>{returnconfig;}' ||
      stripped == 'constmain=config=>config' ||
      stripped.isEmpty) {
    return false;
  }
  return true;
}

Future<bool> hasAnyEnhance({
  required int profileId,
  String? fallbackScriptContent,
}) async {
  final allMerges = await mergeManager.getAll();
  final selectedIds = await mergeManager.getSelectedIds(profileId);
  final activeMerges = allMerges.where(
    (m) => m.isGlobal || selectedIds.contains(m.id),
  );
  for (final merge in activeMerges) {
    final content = await mergeManager.getContent(merge.id);
    if (isNonEmptyYaml(content)) return true;
  }
  if (fallbackScriptContent != null && isNonEmptyScript(fallbackScriptContent)) {
    return true;
  }
  return false;
}

Future<Map<String, dynamic>> applyEnhanceChain({
  required Map<String, dynamic> config,
  required int profileId,
  String? fallbackScriptContent,
}) async {
  var result = Map<String, dynamic>.from(config);

  final allMerges = await mergeManager.getAll();
  final selectedIds = await mergeManager.getSelectedIds(profileId);

  for (final merge in allMerges.where((m) => m.isGlobal)) {
    final content = await mergeManager.getContent(merge.id);
    if (isNonEmptyYaml(content)) {
      final parsed = loadPlainYaml(content);
      if (parsed is Map) {
        result = applyMerge(result, parsed.cast<String, dynamic>());
      }
    }
  }

  for (final id in selectedIds) {
    final merge = allMerges.firstWhereOrNull((m) => m.id == id);
    if (merge != null && !merge.isGlobal) {
      final content = await mergeManager.getContent(merge.id);
      if (isNonEmptyYaml(content)) {
        final parsed = loadPlainYaml(content);
        if (parsed is Map) {
          result = applyMerge(result, parsed.cast<String, dynamic>());
        }
      }
    }
  }

  if (fallbackScriptContent != null &&
      isNonEmptyScript(fallbackScriptContent)) {
    result = await handleEvaluate(fallbackScriptContent, result);
  }

  return result;
}
