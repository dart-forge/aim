/// Primary result codes we branch on. The full list lives in SQLite's docs.
abstract final class SqliteResultCode {
  static const int ok = 0;
  static const int error = 1;
  static const int busy = 5;
  static const int misuse = 21;
  static const int row = 100;
  static const int done = 101;

  /// The low 8 bits of an extended result code are the primary code.
  static int primaryOf(int extended) => extended & 0xff;
}

/// Flags for sqlite3_open_v2.
abstract final class SqliteOpenFlag {
  static const int readOnly = 0x00000001;
  static const int readWrite = 0x00000002;
  static const int create = 0x00000004;
  static const int uri = 0x00000040;

  /// No per-connection mutex. Each connection lives in exactly one isolate,
  /// so nothing else can reach it.
  static const int noMutex = 0x00008000;
}

/// Storage classes returned by sqlite3_column_type.
abstract final class SqliteDataType {
  static const int integer = 1;
  static const int float = 2;
  static const int text = 3;
  static const int blob = 4;
  static const int nullValue = 5;
}
