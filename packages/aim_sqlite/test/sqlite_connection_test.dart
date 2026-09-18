import 'dart:io';

import 'package:aim_sqlite/aim_sqlite.dart';
import 'package:aim_sqlite/src/ffi/bindings.dart';
import 'package:aim_sqlite/src/worker/connection.dart';
import 'package:test/test.dart';

/// SQLITE_READONLY.
const readOnlyResultCode = 8;

void main() {
  late Directory dir;
  late SqliteLibrary library;
  late SqliteConnection writer;

  /// The two flags these tests are about are the ones the writer isolate
  /// never sets, so they are reached here rather than through
  /// SqliteDatabase.
  StatementBatchResult? run(
    SqliteConnection connection,
    String sql, {
    bool wantRows = true,
    bool requireReadOnly = false,
  }) => connection.run(
    sql,
    positional: const [],
    named: const {},
    wantRows: wantRows,
    requireReadOnly: requireReadOnly,
  );

  SqliteConnection open({required bool readOnly}) => SqliteConnection.open(
    library,
    '${dir.path}/app.db',
    readOnly: readOnly,
    busyTimeout: const Duration(seconds: 5),
    synchronous: SqliteSynchronous.full,
  );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('aim_sqlite_connection_test');
    library = SqliteLibrary.open();
    writer = open(readOnly: false);
    run(writer, 'CREATE TABLE t (a INTEGER)', wantRows: false);
  });

  tearDown(() async {
    writer.close();
    await dir.delete(recursive: true);
  });

  test('runs a batch that only reads when only reads are allowed', () {
    final result = run(
      writer,
      'SELECT 1 AS a; SELECT 2 AS b',
      requireReadOnly: true,
    );

    expect(result?.rows, [
      {'b': 2},
    ]);
  });

  test('runs nothing when a batch slips a write in', () {
    final result = run(
      writer,
      'SELECT 1 AS a; INSERT INTO t VALUES (1)',
      requireReadOnly: true,
    );

    expect(result, isNull);
    // The read before the write was prepared but never stepped, so the
    // whole batch is still the writer's to run.
    expect(run(writer, 'SELECT count(*) AS n FROM t')!.rows.single['n'], 0);
  });

  test('a connection opened read-only refuses a write', () {
    final reader = open(readOnly: true);

    try {
      expect(
        () => run(reader, 'INSERT INTO t VALUES (1)', wantRows: false),
        throwsA(
          isA<SqliteException>().having(
            (e) => e.resultCode,
            'resultCode',
            readOnlyResultCode,
          ),
        ),
      );
    } finally {
      reader.close();
    }
  });
}
