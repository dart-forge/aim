import 'dart:ffi';
import 'dart:typed_data';

import 'package:aim_sqlite/src/ffi/bindings.dart';
import 'package:aim_sqlite/src/ffi/result_codes.dart';
import 'package:aim_sqlite/src/sqlite_exception.dart';
import 'package:aim_sqlite/src/sqlite_options.dart';
import 'package:aim_sqlite/src/types/decl_type.dart';
import 'package:aim_sqlite/src/types/raw_value.dart';
import 'package:aim_sqlite/src/types/value_decoder.dart';
import 'package:aim_sqlite/src/types/value_encoder.dart';

/// SQLITE_TRANSIENT: copy the text or blob now, because the caller frees its
/// buffer as soon as the bind call returns.
final Pointer<NativeFunction<Void Function(Pointer<Void>)>> _transient =
    Pointer.fromAddress(-1);

/// sqlite3_bind_text and sqlite3_bind_blob take a C `int` byte count, and
/// dart:ffi narrows a Dart int into it silently, so anything longer would
/// bind truncated instead of failing.
const int _maxBindLength = 0x7FFFFFFF;

/// What a batch of statements returned.
class StatementBatchResult {
  const StatementBatchResult({required this.rows, required this.affected});

  /// The rows of the last statement that had result columns.
  final List<Map<String, Object?>> rows;

  /// sqlite3_changes summed over every statement.
  final int affected;
}

/// One open SQLite connection.
///
/// Lives inside a worker isolate and is the only place in the package that
/// calls libsqlite3. Every method here blocks the isolate it runs on, which
/// is the whole reason there is an isolate to block.
class SqliteConnection {
  SqliteConnection._(this._library, this._handle);

  final SqliteLibrary _library;
  final Pointer<Void> _handle;
  bool _closed = false;

  /// Opens [path]. [readOnly] opens with SQLITE_OPEN_READONLY, which makes
  /// the C library refuse a write even if one gets routed here by mistake.
  static SqliteConnection open(
    SqliteLibrary library,
    String path, {
    required bool readOnly,
    required Duration busyTimeout,
    required SqliteSynchronous synchronous,
  }) {
    // URI filenames so a caller can pass `file:...?mode=memory`; NOMUTEX
    // because a connection never leaves the isolate that opened it.
    final flags = readOnly
        ? SqliteOpenFlag.readOnly | SqliteOpenFlag.uri | SqliteOpenFlag.noMutex
        : SqliteOpenFlag.readWrite |
              SqliteOpenFlag.create |
              SqliteOpenFlag.uri |
              SqliteOpenFlag.noMutex;

    final filename = library.allocateUtf8(path);
    final slot = _pointerSlot<Void>(library);
    final int resultCode;
    final Pointer<Void> handle;
    try {
      resultCode = library.openV2(filename.pointer, slot, flags, nullptr);
      handle = slot.value;
    } finally {
      library.freeMemory(slot.cast());
      library.freeUtf8(filename);
    }

    if (resultCode != SqliteResultCode.ok) {
      // open_v2 hands back a handle even when it fails -- unless it could
      // not allocate one at all -- and that handle still has to be closed.
      final message = handle == nullptr
          ? 'could not open "$path" (result code $resultCode)'
          : library.readCString(library.errmsg(handle)) ?? 'unknown error';
      if (handle != nullptr) library.closeV2(handle);
      throw SqliteException(
        extendedResultCode: resultCode,
        message: message,
        sql: 'open "$path"',
      );
    }

    final connection = SqliteConnection._(library, handle);
    try {
      // Without this, extendedErrcode only ever reports the primary code.
      library.extendedResultCodes(handle, 1);
      library.busyTimeout(handle, busyTimeout.inMilliseconds);
      // SQLite leaves foreign keys off for backwards compatibility.
      connection._driverStatement('PRAGMA foreign_keys = ON');
      if (!readOnly) {
        connection._enableWal();
        connection._driverStatement(
          'PRAGMA synchronous = ${synchronous.pragmaValue}',
        );
      }
    } on Object {
      connection.close();
      rethrow;
    }
    return connection;
  }

  /// Runs every statement in [sql], binding [positional] and [named].
  ///
  /// With [requireReadOnly], prepares them all and checks
  /// sqlite3_stmt_readonly on each BEFORE stepping any of them; if one
  /// writes, nothing runs and null comes back. Without it, prepares and
  /// steps one statement at a time, because a later statement can depend on
  /// an earlier one (`CREATE TABLE t; INSERT INTO t ...` cannot be prepared
  /// before the table exists).
  ///
  /// [wantRows] reads the rows out; without it the statements are still
  /// stepped to the end, so a `RETURNING` clause handed to execute() does
  /// not leave the batch half run.
  ///
  /// Only the first statement of a batch may carry parameters. Statements
  /// are prepared and stepped one at a time, so a later one carrying a
  /// placeholder is refused only once it is reached -- by which point
  /// everything before it has run and committed, and nothing is rolled back.
  StatementBatchResult? run(
    String sql, {
    required List<SqliteBindValue> positional,
    required Map<String, SqliteBindValue> named,
    required bool wantRows,
    required bool requireReadOnly,
  }) {
    // One native buffer for the whole batch: prepare_v2 walks it statement
    // by statement and reports where the next one starts.
    final buffer = _library.allocateUtf8(sql);
    try {
      return requireReadOnly
          ? _runIfReadOnly(
              sql,
              buffer,
              positional: positional,
              named: named,
              wantRows: wantRows,
            )
          : _runInOrder(
              sql,
              buffer,
              positional: positional,
              named: named,
              wantRows: wantRows,
            );
    } finally {
      _library.freeUtf8(buffer);
    }
  }

  /// Opens a transaction and takes the write lock straight away.
  ///
  /// IMMEDIATE rather than SQLite's default DEFERRED: a deferred
  /// transaction starts as a read and only asks for the write lock at its
  /// first write, and that request is refused with SQLITE_BUSY when
  /// another connection wrote in between -- halfway through the caller's
  /// work, where there is nothing useful left to do about it.
  void begin() => _driverStatement('BEGIN IMMEDIATE');

  /// Makes the transaction's writes permanent.
  void commit() => _driverStatement('COMMIT');

  /// Discards the transaction's writes.
  void rollback() => _driverStatement('ROLLBACK');

  /// Closes the connection. Safe to call twice.
  void close() {
    if (_closed) return;
    _closed = true;
    _library.closeV2(_handle);
  }

  /// Prepares, runs and finalises one statement at a time.
  StatementBatchResult _runInOrder(
    String sql,
    SqliteNativeString buffer, {
    required List<SqliteBindValue> positional,
    required Map<String, SqliteBindValue> named,
    required bool wantRows,
  }) {
    final stmtSlot = _pointerSlot<Void>(_library);
    final tailSlot = _pointerSlot<Char>(_library);
    try {
      var offset = 0;
      var index = 0;
      var affected = 0;
      var rows = const <Map<String, Object?>>[];
      while (offset < buffer.byteLength) {
        final stmt = _prepare(sql, buffer, offset, stmtSlot, tailSlot);
        offset = _tailOffset(buffer, tailSlot);
        // Whitespace or a comment: there is nothing to run.
        if (stmt == nullptr) continue;
        try {
          final outcome = _runPrepared(
            sql,
            stmt,
            index,
            positional: positional,
            named: named,
            wantRows: wantRows,
          );
          affected += outcome.affected;
          if (outcome.rows != null) rows = outcome.rows!;
        } finally {
          _library.finalizeStatement(stmt);
        }
        index++;
      }
      return StatementBatchResult(rows: rows, affected: affected);
    } finally {
      _library.freeMemory(tailSlot.cast());
      _library.freeMemory(stmtSlot.cast());
    }
  }

  /// Prepares the whole batch, and runs it only if every statement reads.
  ///
  /// Nothing is stepped until all of them have been checked, so a batch with
  /// a write in it can still be handed back whole for the writer to run.
  StatementBatchResult? _runIfReadOnly(
    String sql,
    SqliteNativeString buffer, {
    required List<SqliteBindValue> positional,
    required Map<String, SqliteBindValue> named,
    required bool wantRows,
  }) {
    final stmtSlot = _pointerSlot<Void>(_library);
    final tailSlot = _pointerSlot<Char>(_library);
    final statements = <Pointer<Void>>[];
    try {
      var offset = 0;
      while (offset < buffer.byteLength) {
        final stmt = _prepare(sql, buffer, offset, stmtSlot, tailSlot);
        offset = _tailOffset(buffer, tailSlot);
        if (stmt != nullptr) statements.add(stmt);
      }
      for (final stmt in statements) {
        if (_library.stmtReadonly(stmt) == 0) return null;
      }
      var affected = 0;
      var rows = const <Map<String, Object?>>[];
      for (var index = 0; index < statements.length; index++) {
        final outcome = _runPrepared(
          sql,
          statements[index],
          index,
          positional: positional,
          named: named,
          wantRows: wantRows,
        );
        affected += outcome.affected;
        if (outcome.rows != null) rows = outcome.rows!;
      }
      return StatementBatchResult(rows: rows, affected: affected);
    } finally {
      for (final stmt in statements) {
        _library.finalizeStatement(stmt);
      }
      _library.freeMemory(tailSlot.cast());
      _library.freeMemory(stmtSlot.cast());
    }
  }

  /// Binds and steps one already prepared statement. [index] is its position
  /// in the batch; the caller finalises it.
  ///
  /// `rows` is null for a statement with no result columns, which is what
  /// keeps a trailing `CREATE TABLE` from wiping the rows of a `SELECT`
  /// earlier in the same batch.
  ({int affected, List<Map<String, Object?>>? rows}) _runPrepared(
    String sql,
    Pointer<Void> stmt,
    int index, {
    required List<SqliteBindValue> positional,
    required Map<String, SqliteBindValue> named,
    required bool wantRows,
  }) {
    _bind(sql, stmt, index, positional: positional, named: named);

    final columnCount = wantRows ? _library.columnCount(stmt) : 0;
    // Resolved once per statement, not once per row.
    final columns = columnCount == 0
        ? const <_Column>[]
        : _resolveColumns(stmt, columnCount);
    final rows = columnCount == 0 ? null : <Map<String, Object?>>[];

    // sqlite3_changes keeps the count from the last statement that reported
    // one, so reading it after a CREATE TABLE would make the DDL claim the
    // rows an earlier INSERT changed. total_changes moves for anything that
    // touched a row -- including rows moved by triggers and foreign key
    // actions -- so it answers "did this statement change anything", while
    // the number itself still comes from changes(), which counts only the
    // rows the statement affected directly.
    final changesBefore = _library.totalChanges(_handle);
    while (true) {
      final resultCode = _library.step(stmt);
      if (resultCode == SqliteResultCode.row) {
        if (rows != null) rows.add(_readRow(stmt, columns));
        continue;
      }
      if (resultCode == SqliteResultCode.done) break;
      throw _exception(sql);
    }
    final changedSomething = _library.totalChanges(_handle) != changesBefore;

    return (
      affected: changedSomething ? _library.changes(_handle) : 0,
      rows: rows,
    );
  }

  /// Compiles the statement that starts [offset] bytes into [buffer], and
  /// leaves the rest of the batch in [tailSlot]. Answers nullptr when what
  /// is left is only whitespace or a comment.
  Pointer<Void> _prepare(
    String sql,
    SqliteNativeString buffer,
    int offset,
    Pointer<Pointer<Void>> stmtSlot,
    Pointer<Pointer<Char>> tailSlot,
  ) {
    stmtSlot.value = nullptr;
    tailSlot.value = nullptr;
    final resultCode = _library.prepareV2(
      _handle,
      Pointer<Char>.fromAddress(buffer.pointer.address + offset),
      buffer.byteLength - offset,
      stmtSlot,
      tailSlot,
    );
    // prepare_v2 leaves the statement null when it fails, so there is
    // nothing to finalise here.
    if (resultCode != SqliteResultCode.ok) throw _exception(sql);
    return stmtSlot.value;
  }

  /// Where the next statement of the batch starts. prepare_v2 points past
  /// the one it just compiled; a null tail can only mean nothing is left.
  int _tailOffset(SqliteNativeString buffer, Pointer<Pointer<Char>> tailSlot) {
    final tail = tailSlot.value;
    if (tail == nullptr) return buffer.byteLength;
    return tail.address - buffer.pointer.address;
  }

  /// Binds [positional] or [named] into [stmt], which is statement [index]
  /// of its batch.
  ///
  /// Only the first statement is bound. A later one carrying placeholders is
  /// rejected rather than left silently holding NULLs, which is the whole
  /// reason parameters and multi-statement SQL do not mix. The rejection
  /// cannot come any earlier than the statement itself on this path, so it
  /// says how much of the batch has already run.
  void _bind(
    String sql,
    Pointer<Void> stmt,
    int index, {
    required List<SqliteBindValue> positional,
    required Map<String, SqliteBindValue> named,
  }) {
    final count = _library.bindParameterCount(stmt);
    if (index > 0) {
      if (count > 0) {
        throw ArgumentError.value(
          sql,
          'sql',
          'only the first statement of a batch can take parameters; the '
              '$index statement(s) before this one have already run and been '
              'committed, so running this call again would apply them twice',
        );
      }
      return;
    }
    if (named.isEmpty) {
      if (count != positional.length) {
        throw ArgumentError.value(
          positional,
          'args',
          'the statement takes $count parameter(s), not ${positional.length}',
        );
      }
      for (var i = 0; i < positional.length; i++) {
        _bindOne(sql, stmt, i + 1, positional[i], 'args[$i]');
      }
      return;
    }
    if (positional.isNotEmpty) {
      throw ArgumentError(
        'pass either args or params to one statement, not both',
      );
    }
    // A missing name would otherwise leave that placeholder NULL, which
    // SQLite would store without complaint.
    if (count != named.length) {
      throw ArgumentError.value(
        named.keys.toList(),
        'params',
        'the statement takes $count parameter(s), not ${named.length}',
      );
    }
    for (final entry in named.entries) {
      _bindOne(
        sql,
        stmt,
        _namedIndex(stmt, entry.key),
        entry.value,
        'params["${entry.key}"]',
      );
    }
  }

  /// The 1-based position of `:name` in [stmt].
  int _namedIndex(Pointer<Void> stmt, String name) {
    final placeholder = _library.allocateUtf8(':$name');
    final int index;
    try {
      index = _library.bindParameterIndex(stmt, placeholder.pointer);
    } finally {
      _library.freeUtf8(placeholder);
    }
    if (index == 0) {
      throw ArgumentError.value(
        name,
        'params',
        'the statement has no parameter named ":$name"',
      );
    }
    return index;
  }

  void _bindOne(
    String sql,
    Pointer<Void> stmt,
    int index,
    SqliteBindValue value,
    String parameter,
  ) {
    final resultCode = switch (value) {
      SqliteBindNull() => _library.bindNull(stmt, index),
      SqliteBindInteger(:final value) => _library.bindInt64(stmt, index, value),
      SqliteBindReal(:final value) => _library.bindDouble(stmt, index, value),
      SqliteBindText(:final value) => _bindText(stmt, index, value, parameter),
      SqliteBindBlob(:final value) => _bindBlob(stmt, index, value, parameter),
    };
    if (resultCode != SqliteResultCode.ok) throw _exception(sql);
  }

  int _bindText(Pointer<Void> stmt, int index, String value, String parameter) {
    final text = _library.allocateUtf8(value);
    try {
      _checkBindLength(text.byteLength, parameter);
      return _library.bindText(
        stmt,
        index,
        text.pointer,
        text.byteLength,
        _transient,
      );
    } finally {
      _library.freeUtf8(text);
    }
  }

  int _bindBlob(
    Pointer<Void> stmt,
    int index,
    Uint8List value,
    String parameter,
  ) {
    _checkBindLength(value.length, parameter);
    // sqlite3_malloc64(0) answers with a null pointer, and bind_blob reads a
    // null pointer as a SQL NULL, so an empty blob still needs a byte.
    final buffer = _library
        .malloc64(value.isEmpty ? 1 : value.length)
        .cast<Uint8>();
    if (buffer == nullptr) throw StateError('sqlite3_malloc64 returned null');
    try {
      if (value.isNotEmpty) buffer.asTypedList(value.length).setAll(0, value);
      return _library.bindBlob(
        stmt,
        index,
        buffer.cast(),
        value.length,
        _transient,
      );
    } finally {
      _library.freeMemory(buffer.cast());
    }
  }

  List<_Column> _resolveColumns(Pointer<Void> stmt, int count) {
    return List.generate(count, (index) {
      // sqlite3 only leaves a column unnamed when it could not allocate the
      // name, which means it is out of memory; the position keeps the row
      // the right shape either way.
      final name =
          _library.readCString(_library.columnName(stmt, index)) ??
          'column$index';
      final declType = normalizeDeclType(
        _library.readCString(_library.columnDeclType(stmt, index)),
      );
      return _Column(name, declType, columnKindFor(declType));
    }, growable: false);
  }

  Map<String, Object?> _readRow(Pointer<Void> stmt, List<_Column> columns) {
    final row = <String, Object?>{};
    for (var index = 0; index < columns.length; index++) {
      final column = columns[index];
      row[column.name] = decodeValue(
        kind: column.kind,
        raw: _readValue(stmt, index, column),
        column: column.name,
        declType: column.declType,
      );
    }
    return row;
  }

  /// Reads column [index] of the current row as SQLite stored it.
  ///
  /// The storage class is checked first and nothing else is touched: the
  /// text and blob accessors answer a SQL NULL with a null pointer, and
  /// reaching for one of them out of turn makes SQLite convert the value in
  /// place and report the converted length.
  SqliteRawValue _readValue(Pointer<Void> stmt, int index, _Column column) {
    switch (_library.columnType(stmt, index)) {
      case SqliteDataType.integer:
        return SqliteRawInteger(_library.columnInt64(stmt, index));
      case SqliteDataType.float:
        return SqliteRawReal(_library.columnDouble(stmt, index));
      case SqliteDataType.text:
        final pointer = _library.columnText(stmt, index);
        final length = _library.columnBytes(stmt, index);
        if (length == 0) return const SqliteRawText('');
        try {
          return SqliteRawText(_library.readUtf8(pointer, length));
        } on FormatException catch (error) {
          // SQLite stores the bytes it was handed and never checks that a
          // TEXT value is UTF-8. Substituting replacement characters would
          // break the driver's promise that a value read from one query can
          // be passed to the next, so this fails instead -- and fails with
          // the column named, which a bare FormatException would not.
          throw SqliteDecodeException(
            column: column.name,
            declType: column.declType,
            rawValue: Uint8List.fromList(
              pointer.cast<Uint8>().asTypedList(length),
            ),
            message:
                'a text column holds bytes that are not UTF-8: '
                '${error.message}',
          );
        }
      case SqliteDataType.blob:
        final pointer = _library.columnBlob(stmt, index);
        final length = _library.columnBytes(stmt, index);
        // A zero length blob comes back as a null pointer.
        if (length == 0) return SqliteRawBlob(Uint8List(0));
        // asTypedList is a view into SQLite's own buffer, which finalize
        // frees, so the bytes are copied out now.
        return SqliteRawBlob(
          Uint8List.fromList(pointer.cast<Uint8>().asTypedList(length)),
        );
      default:
        // SQLITE_NULL, and there is no sixth storage class.
        return const SqliteRawNull();
    }
  }

  /// Switches the journal to WAL, which is what lets a reader run while the
  /// writer is mid-transaction.
  void _enableWal() {
    const sql = 'PRAGMA journal_mode = WAL';
    // The pragma answers with the mode it actually reached.
    final rows = _driverStatement(sql, wantRows: true).rows;
    final mode = rows.length == 1 ? rows.single.values.single : null;
    // A :memory: or temporary database answers 'memory': it has no file to
    // share, so there was never anything WAL could give it. Any other answer
    // means this database cannot use WAL -- an unwritable directory, or a
    // file system with no shared memory for the WAL index.
    if (mode != 'wal' && mode != 'memory') {
      throw SqliteException(
        extendedResultCode: SqliteResultCode.error,
        message:
            'could not put the database in WAL mode (journal_mode is "$mode")',
        sql: sql,
      );
    }
  }

  /// Runs one of the driver's own statements -- a pragma, or one of the
  /// transaction control statements. None of them takes a parameter, and
  /// none of them is ever refused as a write.
  StatementBatchResult _driverStatement(String sql, {bool wantRows = false}) =>
      run(
        sql,
        positional: const [],
        named: const {},
        wantRows: wantRows,
        requireReadOnly: false,
      )!;

  SqliteException _exception(String sql) => SqliteException(
    extendedResultCode: _library.extendedErrcode(_handle),
    message: _library.readCString(_library.errmsg(_handle)) ?? 'unknown error',
    sql: sql,
  );

  static void _checkBindLength(int byteLength, String parameter) {
    if (byteLength > _maxBindLength) {
      throw ArgumentError.value(
        byteLength,
        parameter,
        'is longer than the $_maxBindLength bytes SQLite can bind',
      );
    }
  }
}

/// A result column's name and how its values decode, resolved once per
/// statement instead of once per row.
class _Column {
  const _Column(this.name, this.declType, this.kind);

  final String name;

  /// Normalised, or null when the column has no declared type.
  final String? declType;

  final SqliteColumnKind kind;
}

/// A pointer-sized, NULL-initialised out-parameter. The caller frees it with
/// sqlite3_free.
Pointer<Pointer<T>> _pointerSlot<T extends NativeType>(SqliteLibrary library) {
  final slot = library.malloc64(sizeOf<Pointer<Void>>()).cast<Pointer<T>>();
  if (slot == nullptr) throw StateError('sqlite3_malloc64 returned null');
  slot.value = nullptr;
  return slot;
}
