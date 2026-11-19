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

enum ReleaseNoteKind { heading, bullet, paragraph }

class ReleaseNoteBlock {
  const ReleaseNoteBlock(this.kind, this.text, {this.hasGapBefore = false});

  final ReleaseNoteKind kind;
  final String text;
  final bool hasGapBefore;
}

final _htmlCommentPattern = RegExp(r'<!--.*?-->', dotAll: true);
final _htmlTablePattern = RegExp(
  r'<table\b[^>]*>.*?</table>',
  dotAll: true,
  caseSensitive: false,
);
final _htmlTagLinePattern = RegExp(r'^<[^>]+>$');
final _badgeLinePattern = RegExp(r'^\[!\[[^\]]*\]\([^)]+\)\]\([^)]+\)$');
final _dividerLinePattern = RegExp(r'^[-*_]{3,}$');
final _fullChangelogLinePattern = RegExp(
  r'^\*{0,2}Full Changelog\*{0,2}\s*:',
  caseSensitive: false,
);
final _blockquotePrefixPattern = RegExp(r'^(?:[ \t]*>[ \t]?)+');
final _headingLinePattern = RegExp(r'^#{1,6}[ \t]+(.+?)[ \t]*#*$');
final _bulletLinePattern = RegExp(r'^[ \t]*[-*+][ \t]+(.+)$');

List<String> parseReleaseBody(String? body) {
  if (body == null) return [];
  final regex = RegExp(r'^[ \t]*-[ \t]+(.*)$', multiLine: true);
  return regex
      .allMatches(scopeReleaseNotes(body))
      .map((match) => match.group(1)?.trim() ?? '')
      .where((item) => item.isNotEmpty)
      .toList();
}

List<ReleaseNoteBlock> parseReleaseNotes(String? body) {
  if (body == null) return const [];
  final cleaned = scopeReleaseNotes(
    body,
  ).replaceAll(_htmlCommentPattern, '').replaceAll(_htmlTablePattern, '');
  final blocks = <ReleaseNoteBlock>[];
  var sawBlankLine = false;

  for (final rawLine in cleaned.split(RegExp(r'\r?\n'))) {
    final trimmed = rawLine.trim();
    if (trimmed.isEmpty) {
      sawBlankLine = true;
      continue;
    }
    if (trimmed.startsWith('```') ||
        trimmed.startsWith('~~~') ||
        _htmlTagLinePattern.hasMatch(trimmed) ||
        _badgeLinePattern.hasMatch(trimmed) ||
        _dividerLinePattern.hasMatch(trimmed) ||
        _fullChangelogLinePattern.hasMatch(trimmed)) {
      continue;
    }

    final normalized = rawLine
        .replaceFirst(_blockquotePrefixPattern, '')
        .trim();
    if (normalized.isEmpty) {
      sawBlankLine = true;
      continue;
    }

    final headingMatch = _headingLinePattern.firstMatch(normalized);
    if (headingMatch != null) {
      final text = headingMatch.group(1)!.trim();
      if (text.isNotEmpty) {
        blocks.add(ReleaseNoteBlock(ReleaseNoteKind.heading, text));
        sawBlankLine = false;
      }
      continue;
    }

    final gap =
        sawBlankLine &&
        blocks.isNotEmpty &&
        blocks.last.kind != ReleaseNoteKind.heading;
    final bulletMatch = _bulletLinePattern.firstMatch(normalized);
    if (bulletMatch != null) {
      final text = bulletMatch.group(1)!.trim();
      if (text.isNotEmpty) {
        blocks.add(
          ReleaseNoteBlock(ReleaseNoteKind.bullet, text, hasGapBefore: gap),
        );
        sawBlankLine = false;
      }
      continue;
    }

    blocks.add(
      ReleaseNoteBlock(
        ReleaseNoteKind.paragraph,
        normalized,
        hasGapBefore: gap,
      ),
    );
    sawBlankLine = false;
  }

  return blocks;
}

String scopeReleaseNotes(String body) {
  final begin = body.indexOf(releaseNotesBeginMarker);
  if (begin < 0) return body;
  final start = begin + releaseNotesBeginMarker.length;
  final end = body.indexOf(releaseNotesEndMarker, start);
  return end < 0 ? body.substring(start) : body.substring(start, end);
}
