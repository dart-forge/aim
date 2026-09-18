/// What a column's declared type says its values should become.
///
/// SQLite stores only five storage classes and has no date, boolean or JSON
/// type, so the declared type is the only hint available. A column with no
/// declared type -- an expression or an aggregate -- yields [raw], where the
/// storage class is handed back as is.
enum SqliteColumnKind {
  integer,
  real,

  /// NUMERIC / DECIMAL. Kept as text: a double would break money.
  decimalText,
  boolean,
  text,
  dateTime,
  json,
  blob,

  /// No declared type, or one this driver does not know.
  raw,
}

/// Upper cases [raw] and drops any size, so `varchar(100)` becomes `VARCHAR`.
/// Returns null for null and for a declaration that is only whitespace.
String? normalizeDeclType(String? raw) {
  if (raw == null) return null;
  final head = raw.split('(').first.trim().toUpperCase();
  return head.isEmpty ? null : head;
}

const _kinds = <String, SqliteColumnKind>{
  'INTEGER': SqliteColumnKind.integer,
  'INT': SqliteColumnKind.integer,
  'BIGINT': SqliteColumnKind.integer,
  'SMALLINT': SqliteColumnKind.integer,
  'TINYINT': SqliteColumnKind.integer,
  'REAL': SqliteColumnKind.real,
  'DOUBLE': SqliteColumnKind.real,
  'DOUBLE PRECISION': SqliteColumnKind.real,
  'FLOAT': SqliteColumnKind.real,
  'NUMERIC': SqliteColumnKind.decimalText,
  'DECIMAL': SqliteColumnKind.decimalText,
  'BOOLEAN': SqliteColumnKind.boolean,
  'BOOL': SqliteColumnKind.boolean,
  'TEXT': SqliteColumnKind.text,
  'VARCHAR': SqliteColumnKind.text,
  'CHAR': SqliteColumnKind.text,
  'CLOB': SqliteColumnKind.text,
  'UUID': SqliteColumnKind.text,
  'TIMESTAMP': SqliteColumnKind.dateTime,
  'DATETIME': SqliteColumnKind.dateTime,
  'DATE': SqliteColumnKind.dateTime,
  'JSON': SqliteColumnKind.json,
  'JSONB': SqliteColumnKind.json,
  'BLOB': SqliteColumnKind.blob,
};

/// Resolves the decoder for a column. [declType] must already be normalised.
SqliteColumnKind columnKindFor(String? declType) =>
    _kinds[declType] ?? SqliteColumnKind.raw;
