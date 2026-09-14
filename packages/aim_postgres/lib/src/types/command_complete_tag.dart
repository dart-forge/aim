/// Extracts the row count from a CommandComplete tag such as `INSERT 0 3`,
/// `UPDATE 2` or `SELECT 5`.
///
/// The count is always the last whitespace-separated token. Tags that carry
/// no count (`CREATE TABLE`, `BEGIN`, `SET`, ...) report 0. A trailing NUL
/// from the wire payload is tolerated.
int affectedRowsFromCommandTag(String tag) {
  final trimmed = tag.replaceAll('\x00', '').trim();
  if (trimmed.isEmpty) return 0;
  final lastSpace = trimmed.lastIndexOf(' ');
  final lastToken = lastSpace == -1
      ? trimmed
      : trimmed.substring(lastSpace + 1);
  return int.tryParse(lastToken) ?? 0;
}
