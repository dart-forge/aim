/// Which connection a statement belongs on.
enum SqliteRoute { reader, writer }

const _readKeywords = {'SELECT', 'WITH', 'EXPLAIN'};

/// Picks a connection from the statement's leading keyword.
///
/// This is the FIRST of two stages, and it is not sufficient on its own. It
/// looks at one keyword, so `SELECT 1; INSERT ...` arrives as a read, and a
/// `WITH ... INSERT` arrives as a read too. The reader isolate prepares every
/// statement and checks sqlite3_stmt_readonly before running any of them,
/// handing the whole thing back to the writer if any of them writes.
///
/// Neither stage works alone: sqlite3_stmt_readonly() returns true for BEGIN,
/// COMMIT, ROLLBACK, SAVEPOINT, RELEASE, ATTACH and DETACH, so a check based
/// only on it would put transaction control on a read-only connection. This
/// stage sends those to the writer, where the second stage never sees them.
SqliteRoute routeFor(String sql) {
  final keyword = _leadingKeyword(sql);
  return _readKeywords.contains(keyword)
      ? SqliteRoute.reader
      : SqliteRoute.writer;
}

/// The first bare word, skipping whitespace, `--` comments and `/* */`
/// comments. Empty when there is nothing to run.
String _leadingKeyword(String sql) {
  var i = 0;
  while (i < sql.length) {
    final char = sql[i];
    if (char.trim().isEmpty) {
      i++;
    } else if (sql.startsWith('--', i)) {
      final end = sql.indexOf('\n', i);
      if (end == -1) return '';
      i = end + 1;
    } else if (sql.startsWith('/*', i)) {
      final end = sql.indexOf('*/', i + 2);
      if (end == -1) return '';
      i = end + 2;
    } else {
      break;
    }
  }
  final start = i;
  while (i < sql.length && RegExp(r'[A-Za-z]').hasMatch(sql[i])) {
    i++;
  }
  return sql.substring(start, i).toUpperCase();
}
