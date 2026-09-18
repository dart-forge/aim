import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

// Native / Dart signature pairs. Written out rather than generated so the
// package keeps its only dependency (aim_database) and nothing else.
typedef OpenV2Native = Int Function(
  Pointer<Char>,
  Pointer<Pointer<Void>>,
  Int,
  Pointer<Char>,
);
typedef OpenV2Dart = int Function(
  Pointer<Char>,
  Pointer<Pointer<Void>>,
  int,
  Pointer<Char>,
);

typedef CloseV2Native = Int Function(Pointer<Void>);
typedef CloseV2Dart = int Function(Pointer<Void>);

typedef PrepareV2Native = Int Function(
  Pointer<Void>,
  Pointer<Char>,
  Int,
  Pointer<Pointer<Void>>,
  Pointer<Pointer<Char>>,
);
typedef PrepareV2Dart = int Function(
  Pointer<Void>,
  Pointer<Char>,
  int,
  Pointer<Pointer<Void>>,
  Pointer<Pointer<Char>>,
);

typedef StepNative = Int Function(Pointer<Void>);
typedef StepDart = int Function(Pointer<Void>);

typedef FinalizeStatementNative = Int Function(Pointer<Void>);
typedef FinalizeStatementDart = int Function(Pointer<Void>);

typedef ColumnCountNative = Int Function(Pointer<Void>);
typedef ColumnCountDart = int Function(Pointer<Void>);

typedef ColumnNameNative = Pointer<Char> Function(Pointer<Void>, Int);
typedef ColumnNameDart = Pointer<Char> Function(Pointer<Void>, int);

typedef ColumnDeclTypeNative = Pointer<Char> Function(Pointer<Void>, Int);
typedef ColumnDeclTypeDart = Pointer<Char> Function(Pointer<Void>, int);

typedef ColumnTypeNative = Int Function(Pointer<Void>, Int);
typedef ColumnTypeDart = int Function(Pointer<Void>, int);

typedef ColumnInt64Native = Int64 Function(Pointer<Void>, Int);
typedef ColumnInt64Dart = int Function(Pointer<Void>, int);

typedef ColumnDoubleNative = Double Function(Pointer<Void>, Int);
typedef ColumnDoubleDart = double Function(Pointer<Void>, int);

typedef ColumnTextNative = Pointer<Char> Function(Pointer<Void>, Int);
typedef ColumnTextDart = Pointer<Char> Function(Pointer<Void>, int);

typedef ColumnBlobNative = Pointer<Void> Function(Pointer<Void>, Int);
typedef ColumnBlobDart = Pointer<Void> Function(Pointer<Void>, int);

typedef ColumnBytesNative = Int Function(Pointer<Void>, Int);
typedef ColumnBytesDart = int Function(Pointer<Void>, int);

typedef BindInt64Native = Int Function(Pointer<Void>, Int, Int64);
typedef BindInt64Dart = int Function(Pointer<Void>, int, int);

typedef BindDoubleNative = Int Function(Pointer<Void>, Int, Double);
typedef BindDoubleDart = int Function(Pointer<Void>, int, double);

// The trailing argument is sqlite3's destructor callback for the text/blob
// it was handed (a real function pointer, or the SQLITE_STATIC/TRANSIENT
// sentinels). We always pass a plain Pointer here, never call through it.
typedef BindTextNative = Int Function(
  Pointer<Void>,
  Int,
  Pointer<Char>,
  Int,
  Pointer<NativeFunction<Void Function(Pointer<Void>)>>,
);
typedef BindTextDart = int Function(
  Pointer<Void>,
  int,
  Pointer<Char>,
  int,
  Pointer<NativeFunction<Void Function(Pointer<Void>)>>,
);

typedef BindBlobNative = Int Function(
  Pointer<Void>,
  Int,
  Pointer<Void>,
  Int,
  Pointer<NativeFunction<Void Function(Pointer<Void>)>>,
);
typedef BindBlobDart = int Function(
  Pointer<Void>,
  int,
  Pointer<Void>,
  int,
  Pointer<NativeFunction<Void Function(Pointer<Void>)>>,
);

typedef BindNullNative = Int Function(Pointer<Void>, Int);
typedef BindNullDart = int Function(Pointer<Void>, int);

typedef BindParameterCountNative = Int Function(Pointer<Void>);
typedef BindParameterCountDart = int Function(Pointer<Void>);

typedef BindParameterIndexNative = Int Function(Pointer<Void>, Pointer<Char>);
typedef BindParameterIndexDart = int Function(Pointer<Void>, Pointer<Char>);

typedef ChangesNative = Int Function(Pointer<Void>);
typedef ChangesDart = int Function(Pointer<Void>);

typedef TotalChangesNative = Int Function(Pointer<Void>);
typedef TotalChangesDart = int Function(Pointer<Void>);

typedef ErrmsgNative = Pointer<Char> Function(Pointer<Void>);
typedef ErrmsgDart = Pointer<Char> Function(Pointer<Void>);

typedef ExtendedErrcodeNative = Int Function(Pointer<Void>);
typedef ExtendedErrcodeDart = int Function(Pointer<Void>);

typedef ExtendedResultCodesNative = Int Function(Pointer<Void>, Int);
typedef ExtendedResultCodesDart = int Function(Pointer<Void>, int);

typedef BusyTimeoutNative = Int Function(Pointer<Void>, Int);
typedef BusyTimeoutDart = int Function(Pointer<Void>, int);

typedef StmtReadonlyNative = Int Function(Pointer<Void>);
typedef StmtReadonlyDart = int Function(Pointer<Void>);

typedef Malloc64Native = Pointer<Void> Function(Uint64);
typedef Malloc64Dart = Pointer<Void> Function(int);

typedef FreeMemoryNative = Void Function(Pointer<Void>);
typedef FreeMemoryDart = void Function(Pointer<Void>);

typedef LibversionNumberNative = Int Function();
typedef LibversionNumberDart = int Function();

/// Thrown when libsqlite3 cannot be loaded.
class SqliteLibraryNotFoundException implements Exception {
  SqliteLibraryNotFoundException(this.searched, this.cause);

  /// Every path that was tried, in order.
  final List<String> searched;

  /// The failure from the last attempt.
  final Object cause;

  @override
  String toString() =>
      'SqliteLibraryNotFoundException: could not load libsqlite3. '
      'Looked in: ${searched.join(", ")}. Last error: $cause';
}

/// libsqlite3, loaded and looked up.
///
/// Holds a [DynamicLibrary], so an instance can NOT be sent over a
/// [SendPort]. Every isolate that talks to SQLite opens its own; dlopen is
/// reference counted, so the second open is cheap.
class SqliteLibrary {
  // All 31 symbols are looked up here, eagerly, instead of behind `late
  // final` getters: a missing symbol must fail loudly from open() rather
  // than the first time some unrelated code happens to touch that field.
  SqliteLibrary._(this._library)
    : openV2 = _library.lookupFunction<OpenV2Native, OpenV2Dart>(
        'sqlite3_open_v2',
      ),
      closeV2 = _library.lookupFunction<CloseV2Native, CloseV2Dart>(
        'sqlite3_close_v2',
      ),
      prepareV2 = _library.lookupFunction<PrepareV2Native, PrepareV2Dart>(
        'sqlite3_prepare_v2',
      ),
      step = _library.lookupFunction<StepNative, StepDart>('sqlite3_step'),
      finalizeStatement = _library
          .lookupFunction<FinalizeStatementNative, FinalizeStatementDart>(
            'sqlite3_finalize',
          ),
      columnCount = _library.lookupFunction<ColumnCountNative, ColumnCountDart>(
        'sqlite3_column_count',
      ),
      columnName = _library.lookupFunction<ColumnNameNative, ColumnNameDart>(
        'sqlite3_column_name',
      ),
      columnDeclType = _library
          .lookupFunction<ColumnDeclTypeNative, ColumnDeclTypeDart>(
            'sqlite3_column_decltype',
          ),
      columnType = _library.lookupFunction<ColumnTypeNative, ColumnTypeDart>(
        'sqlite3_column_type',
      ),
      columnInt64 = _library.lookupFunction<ColumnInt64Native, ColumnInt64Dart>(
        'sqlite3_column_int64',
      ),
      columnDouble = _library
          .lookupFunction<ColumnDoubleNative, ColumnDoubleDart>(
            'sqlite3_column_double',
          ),
      columnText = _library.lookupFunction<ColumnTextNative, ColumnTextDart>(
        'sqlite3_column_text',
      ),
      columnBlob = _library.lookupFunction<ColumnBlobNative, ColumnBlobDart>(
        'sqlite3_column_blob',
      ),
      columnBytes = _library.lookupFunction<ColumnBytesNative, ColumnBytesDart>(
        'sqlite3_column_bytes',
      ),
      bindInt64 = _library.lookupFunction<BindInt64Native, BindInt64Dart>(
        'sqlite3_bind_int64',
      ),
      bindDouble = _library.lookupFunction<BindDoubleNative, BindDoubleDart>(
        'sqlite3_bind_double',
      ),
      bindText = _library.lookupFunction<BindTextNative, BindTextDart>(
        'sqlite3_bind_text',
      ),
      bindBlob = _library.lookupFunction<BindBlobNative, BindBlobDart>(
        'sqlite3_bind_blob',
      ),
      bindNull = _library.lookupFunction<BindNullNative, BindNullDart>(
        'sqlite3_bind_null',
      ),
      bindParameterCount = _library
          .lookupFunction<BindParameterCountNative, BindParameterCountDart>(
            'sqlite3_bind_parameter_count',
          ),
      bindParameterIndex = _library
          .lookupFunction<BindParameterIndexNative, BindParameterIndexDart>(
            'sqlite3_bind_parameter_index',
          ),
      changes = _library.lookupFunction<ChangesNative, ChangesDart>(
        'sqlite3_changes',
      ),
      totalChanges = _library
          .lookupFunction<TotalChangesNative, TotalChangesDart>(
            'sqlite3_total_changes',
          ),
      errmsg = _library.lookupFunction<ErrmsgNative, ErrmsgDart>(
        'sqlite3_errmsg',
      ),
      extendedErrcode = _library
          .lookupFunction<ExtendedErrcodeNative, ExtendedErrcodeDart>(
            'sqlite3_extended_errcode',
          ),
      extendedResultCodes = _library
          .lookupFunction<ExtendedResultCodesNative, ExtendedResultCodesDart>(
            'sqlite3_extended_result_codes',
          ),
      busyTimeout = _library.lookupFunction<BusyTimeoutNative, BusyTimeoutDart>(
        'sqlite3_busy_timeout',
      ),
      stmtReadonly = _library
          .lookupFunction<StmtReadonlyNative, StmtReadonlyDart>(
            'sqlite3_stmt_readonly',
          ),
      malloc64 = _library.lookupFunction<Malloc64Native, Malloc64Dart>(
        'sqlite3_malloc64',
      ),
      freeMemory = _library.lookupFunction<FreeMemoryNative, FreeMemoryDart>(
        'sqlite3_free',
      ),
      _libversionNumber = _library
          .lookupFunction<LibversionNumberNative, LibversionNumberDart>(
            'sqlite3_libversion_number',
          );

  /// Checked before the platform defaults, after an explicit path.
  static const String environmentVariable = 'AIM_SQLITE_LIBRARY';

  // Not read again after construction. Kept so every instance transitively
  // holds a DynamicLibrary: the VM refuses to send that through a SendPort,
  // which is exactly the guarantee documented on the class above.
  // ignore: unused_field
  final DynamicLibrary _library;

  /// sqlite3_open_v2.
  final OpenV2Dart openV2;

  /// sqlite3_close_v2.
  final CloseV2Dart closeV2;

  /// sqlite3_prepare_v2.
  final PrepareV2Dart prepareV2;

  /// sqlite3_step.
  final StepDart step;

  /// sqlite3_finalize.
  final FinalizeStatementDart finalizeStatement;

  /// sqlite3_column_count.
  final ColumnCountDart columnCount;

  /// sqlite3_column_name.
  final ColumnNameDart columnName;

  /// sqlite3_column_decltype.
  final ColumnDeclTypeDart columnDeclType;

  /// sqlite3_column_type.
  final ColumnTypeDart columnType;

  /// sqlite3_column_int64.
  final ColumnInt64Dart columnInt64;

  /// sqlite3_column_double.
  final ColumnDoubleDart columnDouble;

  /// sqlite3_column_text.
  final ColumnTextDart columnText;

  /// sqlite3_column_blob.
  final ColumnBlobDart columnBlob;

  /// sqlite3_column_bytes.
  final ColumnBytesDart columnBytes;

  /// sqlite3_bind_int64.
  final BindInt64Dart bindInt64;

  /// sqlite3_bind_double.
  final BindDoubleDart bindDouble;

  /// sqlite3_bind_text.
  final BindTextDart bindText;

  /// sqlite3_bind_blob.
  final BindBlobDart bindBlob;

  /// sqlite3_bind_null.
  final BindNullDart bindNull;

  /// sqlite3_bind_parameter_count.
  final BindParameterCountDart bindParameterCount;

  /// sqlite3_bind_parameter_index.
  final BindParameterIndexDart bindParameterIndex;

  /// sqlite3_changes. Keeps its value from the last DML statement, so it
  /// must not be read after a non-DML statement.
  final ChangesDart changes;

  /// sqlite3_total_changes. Unlike [changes], this also counts rows
  /// changed by triggers and foreign key actions, so a delta in it must
  /// not be treated as an affected-row count.
  final TotalChangesDart totalChanges;

  /// sqlite3_errmsg.
  final ErrmsgDart errmsg;

  /// sqlite3_extended_errcode.
  final ExtendedErrcodeDart extendedErrcode;

  /// sqlite3_extended_result_codes.
  final ExtendedResultCodesDart extendedResultCodes;

  /// sqlite3_busy_timeout.
  final BusyTimeoutDart busyTimeout;

  /// sqlite3_stmt_readonly.
  final StmtReadonlyDart stmtReadonly;

  /// sqlite3_malloc64.
  final Malloc64Dart malloc64;

  /// sqlite3_free.
  final FreeMemoryDart freeMemory;

  /// sqlite3_libversion_number. Use [versionNumber] instead.
  final LibversionNumberDart _libversionNumber;

  /// e.g. 3051000 for 3.51.0.
  int get versionNumber => _libversionNumber();

  static SqliteLibrary open({String? libraryPath}) {
    final searched = candidates(libraryPath, Platform.environment);
    Object? last;
    for (final path in searched) {
      final DynamicLibrary library;
      try {
        library = DynamicLibrary.open(path);
      } on Object catch (error) {
        last = error;
        continue;
      }
      _checkMinimumVersion(library, path);
      // A lookup failure below propagates as-is, naming the missing
      // symbol, instead of being reported as "could not load libsqlite3".
      return SqliteLibrary._(library);
    }
    throw SqliteLibraryNotFoundException(searched, last!);
  }

  /// The paths [open] will try, in order: an explicit [libraryPath] wins
  /// outright and nothing else is tried; otherwise [environmentVariable]
  /// wins if set; otherwise the platform defaults for the current OS.
  ///
  /// Takes the environment as a plain map, rather than reading
  /// [Platform.environment] itself, so this precedence can be tested
  /// without touching the real process environment.
  static List<String> candidates(String? libraryPath, Map<String, String> env) {
    if (libraryPath != null) return [libraryPath];
    final override = env[environmentVariable];
    if (override != null) return [override];
    return _platformDefaults();
  }

  static List<String> _platformDefaults() {
    if (Platform.isMacOS) return ['libsqlite3.dylib'];
    if (Platform.isWindows) return ['sqlite3.dll'];
    return ['libsqlite3.so.0', 'libsqlite3.so'];
  }

  /// sqlite3_malloc64 (3.8.7) is the newest function in the symbol list
  /// below, so that -- not any SQL feature like WAL -- is the actual
  /// floor this driver can run on.
  static const int _minimumVersion = 3008007;

  /// Throws if [library] (opened from [path]) predates [_minimumVersion].
  ///
  /// Checked before any of the other 30 symbols are looked up: an old
  /// libsqlite3 must fail with its version number in the message, not
  /// with a confusing missing-symbol error from whichever new function
  /// happens to be looked up first.
  static void _checkMinimumVersion(DynamicLibrary library, String path) {
    final libversionNumber = library
        .lookupFunction<LibversionNumberNative, LibversionNumberDart>(
          'sqlite3_libversion_number',
        );
    final version = libversionNumber();
    if (version < _minimumVersion) {
      throw SqliteLibraryNotFoundException(
        [path],
        'libsqlite3 at "$path" is version $version, older than the '
        'minimum supported version $_minimumVersion (required by '
        'sqlite3_malloc64)',
      );
    }
  }
}

/// UTF-8 helpers built on SQLite's own allocator, so the package never needs
/// `package:ffi`'s `toNativeUtf8` / `toDartString`.
extension SqliteUtf8 on SqliteLibrary {
  /// Copies [value] into memory owned by SQLite. The caller frees it with
  /// [freeUtf8]. Always NUL terminated, so it can be passed where SQLite
  /// wants a C string, and [byteLength] gives the length where it wants one.
  SqliteNativeString allocateUtf8(String value) {
    final bytes = utf8.encode(value);
    final pointer = malloc64(bytes.length + 1).cast<Uint8>();
    if (pointer == nullptr) throw StateError('sqlite3_malloc64 returned null');
    pointer.asTypedList(bytes.length + 1)
      ..setRange(0, bytes.length, bytes)
      ..[bytes.length] = 0;
    return SqliteNativeString(pointer.cast(), bytes.length);
  }

  void freeUtf8(SqliteNativeString string) => freeMemory(string.pointer.cast());

  /// Reads [length] bytes of UTF-8 from [pointer].
  ///
  /// sqlite3_column_text returns NULL (with a byte count of 0) for a SQL
  /// NULL column, so the caller must branch on the column's storage class
  /// (via columnType) before calling this rather than relying on it to
  /// signal NULL.
  String readUtf8(Pointer<Char> pointer, int length) {
    assert(
      pointer != nullptr || length == 0,
      'readUtf8 called with a null pointer and a non-zero length',
    );
    return utf8.decode(pointer.cast<Uint8>().asTypedList(length));
  }

  /// Reads a NUL terminated C string (for sqlite3_errmsg / _column_name /
  /// _column_decltype, which do not report a length).
  String? readCString(Pointer<Char> pointer) {
    if (pointer == nullptr) return null;
    var length = 0;
    final bytes = pointer.cast<Uint8>();
    while (bytes[length] != 0) {
      length++;
    }
    return utf8.decode(bytes.asTypedList(length));
  }
}

/// A NUL terminated UTF-8 buffer owned by SQLite's allocator.
class SqliteNativeString {
  SqliteNativeString(this.pointer, this.byteLength);

  final Pointer<Char> pointer;

  /// Bytes excluding the NUL terminator.
  final int byteLength;
}
