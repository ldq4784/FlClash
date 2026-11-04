import 'dart:io';

import 'package:fl_clash/common/common.dart';

const globalMergeTemplate = '''# 全局扩展配置 (Global Merge)
# 作用: 对所有订阅生效，在单订阅扩展之前执行
# 支持常规 YAML 属性覆盖，以及特殊的前置/后置插入字段:
#   prepend-rules: 前置规则列表 (插入到现有 rules 最前面)
#   append-rules: 后置规则列表 (插入到现有 rules 最后面)
#   prepend-proxies: 前置节点列表
#   append-proxies: 后置节点列表
#   prepend-proxy-groups: 前置策略组列表
#   append-proxy-groups: 后置策略组列表

# prepend-rules:
#   - DOMAIN-SUFFIX,google.com,DIRECT
''';

const globalScriptTemplate = '''// 全局扩展脚本 (Global Script)
// 作用: 对所有订阅生效，在全局 Merge 之后、单订阅扩展之前执行
//
// 入口函数 main 接收配置对象 config，必须返回处理后的 config 对象
function main(config) {
  return config;
}
''';

const profileMergeTemplate = '''# 订阅扩展配置 (Profile Merge)
# 作用: 仅对当前订阅生效，在全局扩展之后执行
# 支持常规 YAML 属性覆盖，以及特殊的前置/后置插入字段:
#   prepend-rules: 前置规则列表 (插入到现有 rules 最前面)
#   append-rules: 后置规则列表 (插入到现有 rules 最后面)
#   prepend-proxies: 前置节点列表
#   append-proxies: 后置节点列表
#   prepend-proxy-groups: 前置策略组列表
#   append-proxy-groups: 后置策略组列表

# prepend-rules:
#   - DOMAIN-SUFFIX,example.com,DIRECT
''';

const profileScriptTemplate = '''// 订阅扩展脚本 (Profile Script)
// 作用: 仅对当前订阅生效，在扩展链的最后执行
//
// 入口函数 main 接收配置对象 config，必须返回处理后的 config 对象
function main(config) {
  return config;
}
''';

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
  final gmFile = File(await appPath.globalMergePath);
  if (await gmFile.exists() && isNonEmptyYaml(await gmFile.readAsString())) {
    return true;
  }
  final gsFile = File(await appPath.globalScriptPath);
  if (await gsFile.exists() && isNonEmptyScript(await gsFile.readAsString())) {
    return true;
  }
  final pmFile = File(await appPath.getProfileMergePath(profileId));
  if (await pmFile.exists() && isNonEmptyYaml(await pmFile.readAsString())) {
    return true;
  }
  final psFile = File(await appPath.getProfileScriptPath(profileId));
  if (await psFile.exists() && isNonEmptyScript(await psFile.readAsString())) {
    return true;
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

  final gmFile = File(await appPath.globalMergePath);
  if (await gmFile.exists()) {
    final content = await gmFile.readAsString();
    if (isNonEmptyYaml(content)) {
      final parsed = loadPlainYaml(content);
      if (parsed is Map) {
        result = applyMerge(result, parsed.cast<String, dynamic>());
      }
    }
  }

  final gsFile = File(await appPath.globalScriptPath);
  if (await gsFile.exists()) {
    final content = await gsFile.readAsString();
    if (isNonEmptyScript(content)) {
      result = await handleEvaluate(content, result);
    }
  }

  final pmFile = File(await appPath.getProfileMergePath(profileId));
  if (await pmFile.exists()) {
    final content = await pmFile.readAsString();
    if (isNonEmptyYaml(content)) {
      final parsed = loadPlainYaml(content);
      if (parsed is Map) {
        result = applyMerge(result, parsed.cast<String, dynamic>());
      }
    }
  }

  var appliedProfileScript = false;
  final psFile = File(await appPath.getProfileScriptPath(profileId));
  if (await psFile.exists()) {
    final content = await psFile.readAsString();
    if (isNonEmptyScript(content)) {
      result = await handleEvaluate(content, result);
      appliedProfileScript = true;
    }
  }

  if (!appliedProfileScript &&
      fallbackScriptContent != null &&
      isNonEmptyScript(fallbackScriptContent)) {
    result = await handleEvaluate(fallbackScriptContent, result);
  }

  return result;
}
