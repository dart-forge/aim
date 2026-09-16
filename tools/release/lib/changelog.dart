/// Matches a `## Unreleased` heading line, case-insensitively and
/// tolerating trailing spaces/tabs (and a trailing `\r` from CRLF content,
/// which callers strip before matching).
final RegExp _unreleasedHeading = RegExp(
  r'^## unreleased[ \t]*$',
  caseSensitive: false,
);

/// Returns [content] with the release [version] applied.
///
/// - If a `## Unreleased` heading exists, it is renamed to `## [version]`
///   and its entries are kept.
/// - Otherwise, if `## [version]` already exists, [content] is returned
///   unchanged.
/// - Otherwise a `## [version]` block with
///   `See [Release Notes](<repoUrl>/releases/tag/<version>)` is inserted
///   after the first `# ` header, or at the top when there is none.
String bumpChangelog(String content, String version, {required String repoUrl}) {
  final lines = content.split('\n');

  final unreleasedIndex = lines.indexWhere(_isUnreleasedHeadingLine);
  if (unreleasedIndex != -1) {
    final line = lines[unreleasedIndex];
    final hadTrailingCr = line.endsWith('\r');
    lines[unreleasedIndex] = '## $version${hadTrailingCr ? '\r' : ''}';
    return lines.join('\n');
  }

  if (content.contains('## $version')) {
    return content;
  }

  final headerIndex = lines.indexWhere((line) => line.startsWith('# '));

  // Insert right after the top-level header (or at the top when there is
  // none), reusing an existing blank line as the separator instead of
  // adding a second one.
  var insertionIndex = headerIndex + 1;
  if (insertionIndex < lines.length && lines[insertionIndex].isEmpty) {
    insertionIndex++;
  }

  lines.insertAll(insertionIndex, [
    '## $version',
    '',
    'See [Release Notes]($repoUrl/releases/tag/$version)',
    '',
  ]);
  return lines.join('\n');
}

bool _isUnreleasedHeadingLine(String line) {
  final stripped = line.endsWith('\r')
      ? line.substring(0, line.length - 1)
      : line;
  return _unreleasedHeading.hasMatch(stripped);
}
