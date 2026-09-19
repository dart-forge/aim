import 'dart:typed_data';

/// A value as SQLite stored it, before the declared type is applied.
sealed class SqliteRawValue {
  const SqliteRawValue();

  /// The value as Dart sees the storage class itself.
  Object? get value;
}

class SqliteRawInteger extends SqliteRawValue {
  const SqliteRawInteger(this.value);
  @override
  final int value;
}

class SqliteRawReal extends SqliteRawValue {
  const SqliteRawReal(this.value);
  @override
  final double value;
}

class SqliteRawText extends SqliteRawValue {
  const SqliteRawText(this.value);
  @override
  final String value;
}

class SqliteRawBlob extends SqliteRawValue {
  const SqliteRawBlob(this.value);
  @override
  final Uint8List value;
}

class SqliteRawNull extends SqliteRawValue {
  const SqliteRawNull();
  @override
  Object? get value => null;
}
