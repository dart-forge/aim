import 'package:aim_database/aim_database.dart';

/// Converts named parameters (`:id`) to PostgreSQL's positional form (`$1`).
///
/// Returns the rewritten SQL and the values in the order the server will
/// bind them, so `$1` is the first placeholder in the **statement** rather
/// than the first key in [params].
///
/// A name used more than once is rewritten to the same number and its value
/// sent once: PostgreSQL lets one placeholder be referenced repeatedly. A
/// key in [params] that the statement never mentions is left out rather
/// than sent — the generated ORM code builds one map and reuses it across
/// statements that each mention a subset of it.
///
/// Placeholders inside a string literal, a quoted identifier or a comment
/// are left exactly as they are, and a `::` cast is not mistaken for one.
/// Finding them is [scanSqlPlaceholders]'s job.
///
/// Throws [ArgumentError] when the statement uses a name [params] has no
/// value for, and when it mixes a positional `?` in with named parameters.
(String, List<dynamic>) convertNamedParameters(
  String sql,
  Map<String, dynamic> params,
) {
  final placeholders = scanSqlPlaceholders(sql, dialect: SqlDialect.postgres);
  if (placeholders.isEmpty) return (sql, <dynamic>[]);

  if (placeholders.any((placeholder) => placeholder.name == null)) {
    throw ArgumentError(
      'The statement mixes a positional placeholder (?) with named '
      'parameters. Use :name placeholders with params, or ? placeholders '
      'with args, but not both in one statement.',
    );
  }

  final numberByName = <String, int>{};
  final values = <dynamic>[];
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

    final number = numberByName.putIfAbsent(name, () {
      values.add(params[name]);
      return values.length;
    });

    rewritten
      ..write(sql.substring(copiedTo, placeholder.start))
      ..write('\$$number');
    copiedTo = placeholder.end;
  }
  rewritten.write(sql.substring(copiedTo));

  return (rewritten.toString(), values);
}
