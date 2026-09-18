import 'dart:convert';
import 'dart:typed_data';

/// A value ready to hand to one of the sqlite3_bind_* functions.
sealed class SqliteBindValue {
  const SqliteBindValue();
}

class SqliteBindInteger extends SqliteBindValue {
  const SqliteBindInteger(this.value);
  final int value;
}

class SqliteBindReal extends SqliteBindValue {
  const SqliteBindReal(this.value);
  final double value;
}

class SqliteBindText extends SqliteBindValue {
  const SqliteBindText(this.value);
  final String value;
}

class SqliteBindBlob extends SqliteBindValue {
  const SqliteBindBlob(this.value);
  final Uint8List value;
}

class SqliteBindNull extends SqliteBindValue {
  const SqliteBindNull();
}

/// Turns a Dart value into something SQLite can store.
///
/// Everything this returns reads back as the same Dart type, so a value taken
/// from one query can be passed to the next. A type with no representation
/// throws instead of falling back to [Object.toString]: SQLite would take the
/// string without complaint and the mistake would only surface as wrong data
/// much later. [parameter] names the placeholder in the failure.
SqliteBindValue encodeValue(Object? value, {required String parameter}) {
  switch (value) {
    case null:
      return const SqliteBindNull();
    case final int v:
      return SqliteBindInteger(v);
    case final double v:
      return SqliteBindReal(v);
    case final bool v:
      return SqliteBindInteger(v ? 1 : 0);
    case final String v:
      return SqliteBindText(v);
    case final Uint8List v:
      return SqliteBindBlob(v);
    case final DateTime v:
      return SqliteBindText(v.toUtc().toIso8601String());
    case Map() || List():
      try {
        return SqliteBindText(jsonEncode(value));
      } on JsonUnsupportedObjectError catch (error) {
        throw ArgumentError(
          '$parameter cannot be encoded as json: ${error.unsupportedObject}',
        );
      }
    default:
      throw ArgumentError(
        '$parameter has no SQLite representation. Pass an int, double, bool, '
        'String, Uint8List, DateTime, Map, List or null',
      );
  }
}
