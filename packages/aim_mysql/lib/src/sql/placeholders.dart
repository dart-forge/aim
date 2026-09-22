import 'package:aim_database/aim_database.dart';

/// Converts named parameters (`:id`) to MySQL's positional `?` form.
///
/// Returns the rewritten SQL and the values in the order the server will
/// bind them, so the first `?` in the **statement** is paired with the
/// first entry in the returned list, regardless of where its name sits in
/// [params].
///
/// A `?` cannot be bound twice, so a name used more than once in [sql]
/// becomes a separate `?` at each occurrence and its value is repeated once
/// per occurrence. (PostgreSQL's driver does the opposite: it points every
/// occurrence at the same `$1` and sends the value once, because `$1` can be
/// referenced repeatedly.) A key in [params] that [sql] never mentions is
/// left out rather than sent -- generated code passes a whole row's worth of
/// parameters to statements that each use only some of them.
///
/// Placeholders inside a string literal, a quoted identifier or a comment
/// are left exactly as they are, and a `::` cast is not mistaken for one.
/// Finding them is [scanSqlPlaceholders]'s job; [dialect] is passed straight
/// through to it, since `NO_BACKSLASH_ESCAPES` changes where a literal ends
/// and so changes which `:name` sequences are inside one.
///
/// Throws [ArgumentError] when [sql] uses a name [params] has no value for,
/// and when [sql] mixes a positional `?` with named parameters.
(String, List<Object?>) rewriteNamedParameters(
  String sql,
  Map<String, Object?> params, {
  required SqlDialect dialect,
}) {
  final placeholders = scanSqlPlaceholders(sql, dialect: dialect);
  if (placeholders.isEmpty) return (sql, <Object?>[]);

  if (placeholders.any((placeholder) => placeholder.name == null)) {
    throw ArgumentError(
      'The statement mixes a positional placeholder (?) with named '
      'parameters. Use :name placeholders with params, or ? placeholders '
      'with args, but not both in one statement.',
    );
  }

  final values = <Object?>[];
  final rewritten = StringBuffer();
  var copiedTo = 0;

  for (final placeholder in placeholders) {
    final name = placeholder.name!;
    if (!params.containsKey(name)) {
      throw ArgumentError(
        'The statement uses ":$name" but params has no such key. '
        'Given: ${params.keys.join(', ')}',
      );
    }

    values.add(params[name]);

    rewritten
      ..write(sql.substring(copiedTo, placeholder.start))
      ..write('?');
    copiedTo = placeholder.end;
  }
  rewritten.write(sql.substring(copiedTo));

  return (rewritten.toString(), values);
}
