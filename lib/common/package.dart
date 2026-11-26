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
