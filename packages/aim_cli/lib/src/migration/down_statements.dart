/// Reading a migration file: which statements it holds, and how they are
/// allowed to run.
library;

/// Whether the migration whose text is [content] asks to run its statements
/// outside a transaction.
///
/// A few statements cannot run inside a transaction block —
/// `CREATE INDEX CONCURRENTLY` and `VACUUM` among them — and a migration
/// that needs one says so with a line reading `-- aim: no-transaction`. The
/// line may sit anywhere in the file and is not case-sensitive; it covers
/// the whole file, so both the UP and the DOWN section of that migration
/// run a statement at a time.
///
/// The cost of asking for this is that a failure part way through leaves
/// the statements before it applied.
bool runsOutsideTransaction(String content) =>
    _noTransactionMarker.hasMatch(content);

final _noTransactionMarker = RegExp(
  r'^[ \t]*--\s*aim:\s*no-transaction\s*$',
  multiLine: true,
  caseSensitive: false,
);

/// Whether [line] is the marker asking to run outside a transaction.
///
/// It is a comment, so it travels with the statement under it and would
/// otherwise be shown to the operator as if it were a note about that
/// statement.
bool isNoTransactionMarker(String line) =>
    _noTransactionMarker.hasMatch(line.trim());

/// The statements in [sql] that do something.
///
/// Splits on `;` outside comments — a `;` inside a `--` line or a `/* */`
/// block does not end a statement — then drops every fragment that is
/// nothing but comments and whitespace. Returned statements keep their
/// comments, so a note written above a statement still travels with it.
///
/// An empty result means the section cannot roll anything back. Migrations
/// written before the generator could produce these statements hold only
/// `-- TODO` comments; handing those to the server reports success while
/// the schema stays exactly where it was, so a caller has to treat an
/// empty result as "this one cannot be rolled back automatically".
///
/// Single-quoted strings are read as values, so a `;` or a `--` inside one
/// does not end a statement or start a comment; two quotes in a row are one
/// quote in the value. Dollar-quoted strings and backslash escapes are not
/// recognised, and generated migrations do not use them.
List<String> executableStatements(String sql) {
  final statements = <String>[];
  for (final fragment in _splitOnSemicolons(sql)) {
    if (_withoutComments(fragment).trim().isEmpty) continue;
    statements.add(fragment);
  }
  return statements;
}

/// [sql] split on every `;` that is not inside a comment or a string
/// literal. Fragments are trimmed, and empty ones are left out.
List<String> _splitOnSemicolons(String sql) {
  final fragments = <String>[];
  final buffer = StringBuffer();
  var inLineComment = false;
  var inBlockComment = false;
  var inString = false;

  for (var i = 0; i < sql.length; i++) {
    final char = sql[i];
    final next = i + 1 < sql.length ? sql[i + 1] : '';

    if (inLineComment) {
      buffer.write(char);
      if (char == '\n') inLineComment = false;
      continue;
    }
    if (inBlockComment) {
      buffer.write(char);
      if (char == '*' && next == '/') {
        buffer.write(next);
        i++;
        inBlockComment = false;
      }
      continue;
    }
    if (inString) {
      buffer.write(char);
      if (char == "'") {
        // Two quotes in a row are one quote in the value, not the end of
        // the string.
        if (next == "'") {
          buffer.write(next);
          i++;
        } else {
          inString = false;
        }
      }
      continue;
    }

    // Both characters of a comment delimiter are consumed together, so the
    // middle character of `/*/` cannot close the comment it just opened.
    // [_withoutComments] reads the text the same way, and the two have to
    // agree: a fragment split out here and then found empty there would
    // take a real statement with it.
    if (char == '-' && next == '-') {
      inLineComment = true;
      buffer.write(char);
      buffer.write(next);
      i++;
      continue;
    }
    if (char == '/' && next == '*') {
      inBlockComment = true;
      buffer.write(char);
      buffer.write(next);
      i++;
      continue;
    }
    if (char == "'") {
      inString = true;
      buffer.write(char);
      continue;
    }
    if (char == ';') {
      final fragment = buffer.toString().trim();
      if (fragment.isNotEmpty) fragments.add(fragment);
      buffer.clear();
      continue;
    }
    buffer.write(char);
  }

  final last = buffer.toString().trim();
  if (last.isNotEmpty) fragments.add(last);
  return fragments;
}

/// [sql] with `--` lines and `/* */` blocks removed, leaving whatever the
/// server would actually be asked to run. String literals are kept whole,
/// including anything inside them that looks like a comment.
String _withoutComments(String sql) {
  final buffer = StringBuffer();
  var inLineComment = false;
  var inBlockComment = false;
  var inString = false;

  for (var i = 0; i < sql.length; i++) {
    final char = sql[i];
    final next = i + 1 < sql.length ? sql[i + 1] : '';

    if (inLineComment) {
      if (char == '\n') inLineComment = false;
      continue;
    }
    if (inBlockComment) {
      if (char == '*' && next == '/') {
        inBlockComment = false;
        i++;
      }
      continue;
    }
    if (inString) {
      buffer.write(char);
      if (char == "'") {
        if (next == "'") {
          buffer.write(next);
          i++;
        } else {
          inString = false;
        }
      }
      continue;
    }
    if (char == '-' && next == '-') {
      inLineComment = true;
      i++;
      continue;
    }
    if (char == '/' && next == '*') {
      inBlockComment = true;
      i++;
      continue;
    }
    if (char == "'") {
      inString = true;
      buffer.write(char);
      continue;
    }
    buffer.write(char);
  }

  return buffer.toString();
}
