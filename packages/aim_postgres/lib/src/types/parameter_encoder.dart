import 'dart:convert';
import 'dart:typed_data';

import 'package:aim_postgres/src/util.dart';

/// Encodes a Dart value as a text-format query parameter.
///
/// Symmetric with `PgTypeDecoder`: every type the driver returns can be sent
/// back. Returns `null` for `null` (sent as SQL NULL).
///
/// - `int` / `double` / `String`: as is
/// - `bool`: `t` / `f`
/// - `DateTime`: ISO 8601 in UTC
/// - `Uint8List`: bytea hex (`\x...`)
/// - `Map`: JSON (`jsonEncode`)
/// - `List`: PostgreSQL array literal (`{1,"a",NULL}`), elements encoded
///   recursively. To send a JSON array, pass `jsonEncode(list)` as a String.
/// - anything else: `toString()`
String? encodeParameterText(Object? value) {
  if (value == null) return null;
  return switch (value) {
    String s => s,
    int i => i.toString(),
    double d => d.toString(),
    bool b => b ? 't' : 'f',
    DateTime t => t.toUtc().toIso8601String(),
    Uint8List bytes => '\\x${bytesToHex(bytes)}',
    Map<Object?, Object?> m => jsonEncode(m),
    List<Object?> l => _encodeArrayLiteral(l),
    _ => value.toString(),
  };
}

/// [encodeParameterText] as UTF-8 bytes for the Bind message.
Uint8List? encodeParameter(Object? value) {
  final text = encodeParameterText(value);
  return text == null ? null : Uint8List.fromList(utf8.encode(text));
}

String _encodeArrayLiteral(List<Object?> list) {
  final buffer = StringBuffer('{');
  for (var i = 0; i < list.length; i++) {
    if (i > 0) buffer.write(',');
    buffer.write(_encodeArrayElement(list[i]));
  }
  buffer.write('}');
  return buffer.toString();
}

String _encodeArrayElement(Object? element) {
  if (element == null) return 'NULL';
  // Uint8List implements List<int>; it must be treated as bytea, not as a
  // nested array, so test it before the generic List case.
  if (element is List<Object?> && element is! Uint8List) {
    return _encodeArrayLiteral(element);
  }
  final text = encodeParameterText(element)!;
  // Numbers and booleans are safe unquoted. Everything else (strings, dates,
  // bytea, json) is quoted so commas, braces, quotes and backslashes cannot
  // be misread as syntax.
  if (element is num || element is bool) return text;
  return '"${text.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
}
