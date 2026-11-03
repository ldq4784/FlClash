import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

import 'common.dart';

extension PackageInfoExtension on PackageInfo {
  String get ua => [
    '$appName/v$version',
    'clash-verge',
    'Platform/${Platform.operatingSystem}',
  ].join(' ');
}

int compareVersions(String version1, String version2) {
  final clean1 = version1.split('+')[0].split('-')[0];
  final clean2 = version2.split('+')[0].split('-')[0];
  final List<String> v1 = clean1.split('.');
  final List<String> v2 = clean2.split('.');
  final int major1 = v1.isNotEmpty ? _parseSegment(v1[0]) : 0;
  final int major2 = v2.isNotEmpty ? _parseSegment(v2[0]) : 0;
  if (major1 != major2) {
    return major1.compareTo(major2);
  }
  final int minor1 = v1.length > 1 ? _parseSegment(v1[1]) : 0;
  final int minor2 = v2.length > 1 ? _parseSegment(v2[1]) : 0;
  if (minor1 != minor2) {
    return minor1.compareTo(minor2);
  }
  final int patch1 = v1.length > 2 ? _parseSegment(v1[2]) : 0;
  final int patch2 = v2.length > 2 ? _parseSegment(v2[2]) : 0;
  if (patch1 != patch2) {
    return patch1.compareTo(patch2);
  }
  final int build1 = _extractBuild(version1);
  final int build2 = _extractBuild(version2);
  return build1.compareTo(build2);
}

int _parseSegment(String s) {
  final match = RegExp(r'^\d+').firstMatch(s);
  return match != null ? int.parse(match.group(0)!) : 0;
}

int _extractBuild(String version) {
  if (version.contains('+')) {
    return _parseSegment(version.split('+')[1]);
  }
  final match = RegExp(
    r'[-.]build[.-]?(\d+)',
    caseSensitive: false,
  ).firstMatch(version);
  if (match != null) {
    return int.parse(match.group(1)!);
  }
  return 0;
}

const releaseNotesBeginMarker = '<!-- flclash:changelog:begin -->';
const releaseNotesEndMarker = '<!-- flclash:changelog:end -->';

List<String> parseReleaseBody(String? body) {
  if (body == null) return [];
  final regex = RegExp(r'^[ \t]*-[ \t]+(.*)$', multiLine: true);
  return regex
      .allMatches(scopeReleaseNotes(body))
      .map((match) => match.group(1)?.trim() ?? '')
      .where((item) => item.isNotEmpty)
      .toList();
}

String scopeReleaseNotes(String body) {
  final begin = body.indexOf(releaseNotesBeginMarker);
  if (begin < 0) return body;
  final start = begin + releaseNotesBeginMarker.length;
  final end = body.indexOf(releaseNotesEndMarker, start);
  return end < 0 ? body.substring(start) : body.substring(start, end);
}
