/// Reading a migration's DOWN section as statements to run.
library;

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
/// String literals are not tracked, so a `;` inside one splits the
/// statement. Generated migrations do not contain such literals.
List<String> executableStatements(String sql) {
  final statements = <String>[];
  for (final fragment in _splitOnSemicolons(sql)) {
    if (_withoutComments(fragment).trim().isEmpty) continue;
    statements.add(fragment);
  }
  return statements;
}

/// [sql] split on every `;` that is not inside a comment. Fragments are
/// trimmed, and empty ones are left out.
List<String> _splitOnSemicolons(String sql) {
  final fragments = <String>[];
  final buffer = StringBuffer();
  var inLineComment = false;
  var inBlockComment = false;

  for (var i = 0; i < sql.length; i++) {
    final char = sql[i];
    final next = i + 1 < sql.length ? sql[i + 1] : '';

    if (!inBlockComment && char == '-' && next == '-') {
      inLineComment = true;
      buffer.write(char);
      continue;
    }
    if (inLineComment && char == '\n') {
      inLineComment = false;
      buffer.write(char);
      continue;
    }
    if (!inLineComment && char == '/' && next == '*') {
      inBlockComment = true;
      buffer.write(char);
      continue;
    }
    if (inBlockComment && char == '*' && next == '/') {
      inBlockComment = false;
      buffer.write(char);
      continue;
    }
    if (char == ';' && !inLineComment && !inBlockComment) {
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
/// server would actually be asked to run.
String _withoutComments(String sql) {
  final buffer = StringBuffer();
  var inLineComment = false;
  var inBlockComment = false;

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
    buffer.write(char);
  }

  return buffer.toString();
}
