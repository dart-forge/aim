/// Where a parameter placeholder sits in a SQL string.
final class SqlPlaceholder {
  const SqlPlaceholder({
    required this.start,
    required this.end,
    required this.name,
  });

  /// Index of the leading `:` or `?`.
  final int start;

  /// Index just past the placeholder's last character.
  final int end;

  /// The name without its leading colon, or null for a positional `?`.
  final String? name;

  @override
  String toString() => 'SqlPlaceholder(${name ?? '?'} at $start..$end)';
}

/// The lexical rules that decide where a string literal, a quoted identifier
/// or a comment begins and ends.
///
/// Only what differs between the dialects this package serves is here. What
/// they share is built into [scanSqlPlaceholders]: `'...'` and `"..."`
/// closed by a doubled quote, `--` to the end of the line, and
/// `/* ... */`.
///
/// Whether a double-quoted run is a string (MySQL) or an identifier
/// (Postgres) is deliberately not a field. A placeholder cannot appear
/// inside either, so for this purpose the two are the same thing: a run to
/// skip.
final class SqlDialect {
  const SqlDialect({
    required this.identifierQuote,
    required this.backslashEscapes,
    required this.hashLineComment,
    this.doubleDashCommentNeedsBoundary = false,
  });

  /// A quoting character beyond `'` and `"`, or null when the dialect has
  /// none. MySQL quotes identifiers with a backtick.
  final String? identifierQuote;

  /// Whether a backslash inside a quoted run escapes the next character.
  ///
  /// Only ever applies inside a `'` or `"` string literal, never inside a
  /// run opened by [identifierQuote]: MySQL's own rule is that a backslash
  /// has no special meaning in a quoted identifier, escaping or otherwise,
  /// so `` `a\` `` is the two-character identifier `a\`, not an escaped
  /// backtick that swallows whatever follows.
  final bool backslashEscapes;

  /// Whether `#` starts a comment that runs to the end of the line.
  final bool hashLineComment;

  /// Whether `--` only starts a comment when followed by whitespace, a
  /// control character or the end of the string -- MySQL's actual rule,
  /// unlike Postgres, where `--` is always a comment regardless of what
  /// comes after it.
  ///
  /// This matters for a placeholder right after it: MySQL reads
  /// `SELECT 1--:x` as the expression `1 - -:x`, with `:x` a placeholder --
  /// not as `1` followed by a comment that swallows `:x`.
  final bool doubleDashCommentNeedsBoundary;

  /// PostgreSQL.
  ///
  /// A backslash is an ordinary character: `standard_conforming_strings` has
  /// been on by default since 9.1, so `'a\'` is a complete literal holding a
  /// backslash rather than an escaped quote.
  ///
  /// Not handled, here or anywhere in this package: `E'...'` strings, where
  /// a backslash *does* escape, and `$tag$...$tag$` dollar quoting. SQL
  /// using either is scanned as though the quoting were ordinary, which can
  /// misplace the end of the literal. Nothing in this repository emits
  /// either form.
  static const postgres = SqlDialect(
    identifierQuote: null,
    backslashEscapes: false,
    hashLineComment: false,
  );

  /// MySQL with its default `sql_mode`.
  static const mysql = SqlDialect(
    identifierQuote: '`',
    backslashEscapes: true,
    hashLineComment: true,
    doubleDashCommentNeedsBoundary: true,
  );

  /// MySQL with `NO_BACKSLASH_ESCAPES` in its `sql_mode`, where a backslash
  /// inside a literal is an ordinary character.
  ///
  /// A driver has to read `sql_mode` to know which of the two to use. The
  /// same SQL means different things under them: in `'a\' , :x'` the literal
  /// ends after the backslash under this dialect and swallows `:x` under
  /// [mysql].
  static const mysqlWithoutBackslashEscapes = SqlDialect(
    identifierQuote: '`',
    backslashEscapes: false,
    hashLineComment: true,
    doubleDashCommentNeedsBoundary: true,
  );
}

/// Every parameter placeholder in [sql] that is not inside a string literal,
/// a quoted identifier or a comment, in the order they appear.
///
/// A named placeholder is `:` followed by one or more letters, digits or
/// underscores, and the **whole** run is the name — so `:user_id` is never
/// read as `:user` followed by `_id`. A positional placeholder is a bare
/// `?` and its [SqlPlaceholder.name] is null.
///
/// The same name appearing more than once is reported at each position.
/// What to do about that is the caller's: MySQL has to repeat the argument
/// because a `?` cannot be reused, while Postgres can point every position
/// at one `$1`.
///
/// An unterminated literal or comment swallows the rest of the string.
/// Finding nothing there is deliberate: the statement is already malformed,
/// and a placeholder the server would never see as one is worse than none.
List<SqlPlaceholder> scanSqlPlaceholders(
  String sql, {
  required SqlDialect dialect,
}) {
  final found = <SqlPlaceholder>[];
  var i = 0;

  while (i < sql.length) {
    final char = sql[i];

    if (char == '-' && sql.startsWith('--', i)) {
      final boundaryOk = !dialect.doubleDashCommentNeedsBoundary ||
          i + 2 >= sql.length ||
          _isCommentBoundary(sql[i + 2]);
      if (boundaryOk) {
        final end = sql.indexOf('\n', i);
        if (end == -1) break;
        i = end + 1;
        continue;
      }
    }

    if (dialect.hashLineComment && char == '#') {
      final end = sql.indexOf('\n', i);
      if (end == -1) break;
      i = end + 1;
      continue;
    }

    if (char == '/' && sql.startsWith('/*', i)) {
      final end = sql.indexOf('*/', i + 2);
      if (end == -1) break;
      i = end + 2;
      continue;
    }

    if (char == "'" || char == '"' || char == dialect.identifierQuote) {
      final isIdentifierQuote = char == dialect.identifierQuote;
      i = _skipQuoted(
        sql,
        i,
        char,
        !isIdentifierQuote && dialect.backslashEscapes,
      );
      continue;
    }

    if (char == '?') {
      found.add(SqlPlaceholder(start: i, end: i + 1, name: null));
      i++;
      continue;
    }

    if (char == ':') {
      // `::` is a Postgres cast. Stepping over both matters: stepping over
      // one would leave the second colon to be read as the start of a
      // placeholder named after the type.
      if (sql.startsWith('::', i)) {
        i += 2;
        continue;
      }

      var end = i + 1;
      while (end < sql.length && _isNameChar(sql[end])) {
        end++;
      }
      if (end > i + 1) {
        found.add(
          SqlPlaceholder(start: i, end: end, name: sql.substring(i + 1, end)),
        );
        i = end;
        continue;
      }
      // A colon followed by anything else — `:=`, or a stray one — is not a
      // placeholder.
      i++;
      continue;
    }

    i++;
  }

  return found;
}

/// The index just past the quoted run that opens at [openIndex], or the end
/// of [sql] when the run is never closed.
int _skipQuoted(
  String sql,
  int openIndex,
  String quote,
  bool backslashEscapes,
) {
  var i = openIndex + 1;
  while (i < sql.length) {
    final char = sql[i];

    if (backslashEscapes && char == r'\' && i + 1 < sql.length) {
      i += 2;
      continue;
    }

    if (char == quote) {
      // A doubled quote is an escaped quote, not the end of the run.
      if (i + 1 < sql.length && sql[i + 1] == quote) {
        i += 2;
        continue;
      }
      return i + 1;
    }

    i++;
  }
  return sql.length;
}

/// Whether [char] is whitespace or a control character -- what MySQL
/// requires right after `--` for it to start a comment, rather than be read
/// as two unary minuses.
bool _isCommentBoundary(String char) {
  final code = char.codeUnitAt(0);
  return code <= 0x20;
}

bool _isNameChar(String char) {
  final code = char.codeUnitAt(0);
  return (code >= 0x61 && code <= 0x7a) || // a-z
      (code >= 0x41 && code <= 0x5a) || // A-Z
      (code >= 0x30 && code <= 0x39) || // 0-9
      code == 0x5f; // _
}
