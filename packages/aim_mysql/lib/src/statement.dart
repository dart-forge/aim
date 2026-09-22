import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:aim_mysql/src/connection.dart';
import 'package:aim_mysql/src/exceptions.dart';
import 'package:aim_mysql/src/protocol/packets.dart';
import 'package:aim_mysql/src/protocol/wire.dart';
import 'package:aim_mysql/src/types/column_type.dart';
import 'package:aim_mysql/src/types/value_decoder.dart';
import 'package:aim_mysql/src/types/value_encoder.dart';

/// The command bytes this file sends. Each is the first byte of the
/// packet it names.
const int _comStmtPrepare = 0x16;
const int _comStmtExecute = 0x17;
const int _comStmtClose = 0x19;

/// `ER_NEED_REPREPARE`: the table a prepared statement named changed shape
/// underneath it, and the server has dropped the statement rather than run
/// it against a definition that no longer matches. See
/// [withReprepareRetry].
const int _erNeedReprepare = 1615;

/// `SERVER_STATUS_MORE_RESULTS_EXISTS`: set on the packet that ends a
/// result set when another one follows in the same reply -- the only way
/// `CALL`ing a procedure that runs several SELECTs is told apart from one
/// that runs a single one. See [_readResultSets].
const int _serverMoreResultsExists = 0x0008;

/// One statement the server has prepared and assigned an id to.
final class PreparedStatement {
  PreparedStatement({
    required this.id,
    required this.parameterCount,
    required this.columns,
    this.sql,
  });

  /// The id the server assigned this statement, scoped to the connection
  /// that prepared it. Sending it down a different connection would
  /// execute whatever statement that connection happens to have under the
  /// same number, or nothing at all -- which is why [StatementCache] is
  /// per connection rather than shared across a pool.
  final int id;

  /// How many `?` placeholders this statement takes.
  final int parameterCount;

  /// The result shape this statement was prepared with, straight from the
  /// prepare response. Empty for a statement that returns no rows.
  final List<ColumnDefinition> columns;

  /// The SQL text this statement was prepared from, when it came from a
  /// [StatementCache] rather than being constructed directly -- as the
  /// cache's own tests do, with no error to recover from and so no need
  /// for this.
  ///
  /// [executeStatement] needs this to re-prepare after error 1615
  /// (`ER_NEED_REPREPARE`): without it, the statement runs once and any
  /// error -- 1615 included -- simply propagates, since there is no SQL
  /// text left to re-prepare from.
  final String? sql;
}

/// One result set: the rows a `SELECT` produced, or the rowless
/// accounting an `INSERT`/`UPDATE`/`DELETE` produced instead.
final class MySqlResult {
  MySqlResult({
    required this.columns,
    required this.rows,
    required this.affectedRows,
    required this.lastInsertId,
    required this.moreResults,
  });

  /// Empty for a result set with no rows: an OK reply carries no column
  /// metadata at all, not even naming zero columns.
  final List<ColumnDefinition> columns;

  final List<List<Object?>> rows;

  /// `0` for a result set that has rows -- only an OK-only result set
  /// (an `INSERT`/`UPDATE`/`DELETE`, or a non-`SELECT` statement inside a
  /// `CALL`) reports a nonzero count here.
  final int affectedRows;

  /// `0` when this result set generated no auto-increment value.
  final int lastInsertId;

  /// Whether `SERVER_MORE_RESULTS_EXISTS` was set on the packet that ended
  /// this result set, meaning another one follows in the same reply.
  /// Consumed by [_readResultSets] while reading; a caller looking at a
  /// finished [MySqlResultSets] reads [MySqlResultSets.sets] instead of
  /// this field on any one entry.
  final bool moreResults;
}

/// Every result set one `COM_STMT_EXECUTE` or `COM_QUERY` reply carried.
///
/// A single call can produce more than one: `CALL`ing a procedure that
/// runs several `SELECT`s is the ordinary way this happens. [sets] is
/// never empty -- even a statement with no rows and nothing more to follow
/// produces the one OK-only set that says so.
final class MySqlResultSets {
  MySqlResultSets(this.sets);

  /// Every result set the reply carried, in the order the server sent
  /// them.
  final List<MySqlResult> sets;

  /// The one set that has rows, or `null` when none does.
  ///
  /// Throws [MySqlProtocolException] when more than one set has rows.
  /// A caller reading rows gets back a single list from a single call;
  /// silently returning the first such set and dropping the rest would
  /// hide rows the server actually sent, which is worse than refusing to
  /// guess which one was wanted.
  MySqlResult? get withRows {
    final withRows = sets.where((set) => set.rows.isNotEmpty).toList();
    if (withRows.length > 1) {
      throw MySqlProtocolException(
        'this call produced ${withRows.length} result sets with rows; at '
        'most one is supported here, since a caller reading rows gets '
        'back a single list',
      );
    }
    return withRows.isEmpty ? null : withRows.single;
  }

  /// Every set's [MySqlResult.affectedRows], added up -- e.g. for a `CALL`
  /// whose procedure runs several `INSERT`/`UPDATE` statements.
  int get totalAffectedRows =>
      sets.fold(0, (total, set) => total + set.affectedRows);

  /// The last non-zero [MySqlResult.lastInsertId] across every set, in the
  /// order the server sent them, or `0` if none reported one.
  ///
  /// Mirrors how MySQL's own `LAST_INSERT_ID()` reads back after a `CALL`
  /// runs several statements: whichever one last generated an id is the
  /// one it reflects, even if a later statement in the same call (a
  /// `SELECT`, say) generated none of its own.
  ///
  /// The wire protocol permits this shape: while
  /// `SERVER_MORE_RESULTS_EXISTS` stays set, the server may send as many
  /// OK packets as it likes, each with its own `affectedRows` and
  /// `lastInsertId`, so a set with a real id followed by one reporting
  /// `0` is not hypothetical. It is not one a real MySQL 8.0 or 8.4
  /// server was found to produce, though: `CALL`ing a procedure with two
  /// plain `INSERT`s collapsed both into a single result set reporting
  /// `affectedRows: 1` and `lastInsertId: 0`, even though both rows
  /// genuinely landed. So this rule is pinned by constructing
  /// [MySqlResultSets] directly in a unit test rather than through an
  /// integration test that calls a real procedure -- the same situation
  /// as [withReprepareRetry]'s policy, and the same answer to it: the
  /// natural trigger does not reach this shape on these server versions,
  /// not that nobody wrote the test.
  int get lastInsertId {
    var last = 0;
    for (final set in sets) {
      if (set.lastInsertId != 0) {
        last = set.lastInsertId;
      }
    }
    return last;
  }
}

/// A per-connection cache of prepared statements, keyed by SQL text.
///
/// [prepare] and [close] are injected rather than reaching for a
/// [MySqlConnection] directly, so the cache's own eviction and
/// deduplication logic can be tested without a server -- see
/// [statementCacheFor] for how a real connection wires them up.
final class StatementCache {
  StatementCache({
    required this.capacity,
    required this.prepare,
    required this.close,
  });

  /// The most entries this cache holds before evicting the least recently
  /// used one. See [statementCacheFor] for how a real connection picks
  /// this against the server's own limit on how many prepared statements
  /// may exist at once.
  final int capacity;

  final Future<PreparedStatement> Function(String sql) prepare;
  final Future<void> Function(int id) close;

  /// Every entry currently held, oldest (least recently used) first: a
  /// [Map] iterates in insertion order, and [get] re-inserts a key it
  /// already has to move it to the newest end. The value is the `Future`
  /// [prepare] returned, not the [PreparedStatement] it resolves to, so
  /// that two callers asking for the same [sql] at once share the one
  /// in-flight prepare instead of each starting their own.
  final Map<String, Future<PreparedStatement>> _entries = {};

  int get size => _entries.length;

  /// The prepared statement for [sql]: the cached one, if [sql] was asked
  /// for before and has not been [invalidate]d or evicted since, otherwise
  /// a freshly [prepare]d one.
  ///
  /// Deliberately not `async`: the cache lookup, and on a miss the call to
  /// [prepare] and the insertion into the cache, all happen synchronously
  /// before this returns, with no `await` in between. That is what lets
  /// two calls for the same [sql] made back to back -- before either has
  /// had a chance to resolve -- see each other, so the second finds what
  /// the first already inserted instead of both racing to prepare the
  /// same statement.
  Future<PreparedStatement> get(String sql) {
    final existing = _entries.remove(sql);
    if (existing != null) {
      _entries[sql] = existing; // Re-insert: now the most recently used.
      return existing;
    }

    final future = prepare(sql);
    _entries[sql] = future;
    _evictIfNeeded();
    return _forgetOnFailure(sql, future);
  }

  /// Awaits [future], dropping [sql]'s entry first if it fails.
  ///
  /// Without this, a transient failure would poison the entry for the
  /// rest of the connection's life: nothing else ever removes a failed
  /// prepare, so every later [get] for the same [sql] would replay the
  /// same exception forever instead of trying again.
  Future<PreparedStatement> _forgetOnFailure(
    String sql,
    Future<PreparedStatement> future,
  ) async {
    try {
      return await future;
    } catch (_) {
      // Only this entry, and only if nothing else already replaced or
      // dropped it -- an invalidate or an eviction racing with this same
      // failure must not remove a different, unrelated entry.
      if (identical(_entries[sql], future)) {
        _entries.remove(sql);
      }
      rethrow;
    }
  }

  /// Drops the cached entry for [sql], if there is one, without closing it
  /// on the server.
  ///
  /// This is for a statement the server has already invalidated by the
  /// time this is called -- error 1615, `ER_NEED_REPREPARE` -- so closing
  /// an id the server has already dropped would itself be an error. The
  /// entry is simply forgotten, and the next [get] prepares a new one.
  void invalidate(String sql) {
    _entries.remove(sql);
  }

  /// Closes every statement this cache holds and empties it.
  ///
  /// Best-effort throughout: a prepare that never succeeded has nothing to
  /// close, and a [close] call that fails -- most likely because the
  /// connection is already unusable -- is not reported back to whoever
  /// called this. [MySqlConnection.close] is the main caller, and it must
  /// not itself fail just because a courtesy notice to the server could
  /// not be sent on the way out.
  Future<void> clear() async {
    final entries = _entries.values.toList();
    _entries.clear();
    for (final future in entries) {
      await _closeQuietly(future);
    }
  }

  void _evictIfNeeded() {
    while (_entries.length > capacity) {
      final oldestKey = _entries.keys.first;
      final evicted = _entries.remove(oldestKey)!;
      // Deliberately not awaited: eviction is a side effect of some other
      // caller's `get`, who is waiting on a different statement entirely
      // and must not be held up by how long closing this one takes.
      unawaited(_closeQuietly(evicted));
    }
  }

  Future<void> _closeQuietly(Future<PreparedStatement> future) async {
    PreparedStatement statement;
    try {
      statement = await future;
    } catch (_) {
      return; // Its own prepare failed; there is nothing to close.
    }
    try {
      await close(statement.id);
    } catch (_) {
      // Best-effort -- see clear()'s doc comment.
    }
  }
}

/// The most prepared statements a single connection's cache holds before
/// evicting the least recently used one.
///
/// The server's own `max_prepared_stmt_count` defaults to 16382 and is
/// shared across every connection to the server, not given to each one
/// separately. A per-connection cap has to leave headroom for however many
/// connections a pool opens at once; 64 does that with room to spare.
const int _defaultStatementCacheCapacity = 64;

/// Builds the [StatementCache] a [MySqlConnection] owns: [StatementCache.prepare]
/// and [StatementCache.close] wired to run `COM_STMT_PREPARE` and
/// `COM_STMT_CLOSE` on [connection].
StatementCache statementCacheFor(MySqlConnection connection) => StatementCache(
  capacity: _defaultStatementCacheCapacity,
  prepare: (sql) => _prepareStatement(connection, sql),
  close: (id) => _closeStatement(connection, id),
);

/// Runs `COM_STMT_PREPARE` for [sql] and reads its reply.
///
/// Reply layout:
/// ```
/// 0x00 | int4 statement_id | int2 column_count | int2 parameter_count
/// | int1 reserved | int2 warning_count
/// parameter_count column definitions -- none sent if it is 0
/// column_count column definitions    -- none sent if it is 0
/// ```
/// `CLIENT_DEPRECATE_EOF` is always among this driver's negotiated
/// capabilities, so no EOF packet follows either group.
///
/// The `0x00` case is deliberately not read with [parseCommandPacket]:
/// that function's `0x00` branch parses an *OK* packet's layout (lenenc
/// affected-rows, lenenc last-insert-id, ...), which shares only its
/// leading byte with this reply. Reading this payload through it would
/// misread the statement id's own bytes as those fields instead.
Future<PreparedStatement> _prepareStatement(
  MySqlConnection connection,
  String sql,
) {
  return connection.exchange<PreparedStatement>(
    _comStmtPrepare,
    utf8.encode(sql),
    (reader) async {
      final header = await reader.next();
      if (header.isEmpty) {
        throw MySqlProtocolException(
          'empty payload replying to COM_STMT_PREPARE',
        );
      }
      if (header[0] == 0xff) {
        throw mysqlErrorFor(parseCommandPacket(header) as ErrPacket);
      }
      if (header[0] != 0x00) {
        throw MySqlProtocolException(
          'expected OK or ERR replying to COM_STMT_PREPARE, got a leading '
          'byte of 0x${header[0].toRadixString(16).padLeft(2, "0")}',
        );
      }

      final headerReader = ByteReader(header);
      headerReader.readUint8(); // The 0x00 marker; already acted on.
      final statementId = headerReader.readUint32();
      final columnCount = headerReader.readUint16();
      final parameterCount = headerReader.readUint16();
      headerReader.skip(1); // Reserved.
      headerReader.readUint16(); // Warning count; not surfaced.

      for (var i = 0; i < parameterCount; i++) {
        await reader.next(); // Parameter column definition; not needed here.
      }
      final columns = [
        for (var i = 0; i < columnCount; i++)
          parseColumnDefinition(await reader.next()),
      ];

      return PreparedStatement(
        id: statementId,
        parameterCount: parameterCount,
        columns: columns,
        sql: sql,
      );
    },
  );
}

/// Sends `COM_STMT_CLOSE` for [id] and returns without reading anything
/// back.
///
/// `COM_STMT_CLOSE` has no reply at all, unlike `COM_STMT_RESET`, which
/// does have one. Calling `reader.next()` here would wait forever for a
/// packet the server never sends, hanging every cache eviction -- and
/// every [MySqlConnection.close] -- until a timeout.
Future<void> _closeStatement(MySqlConnection connection, int id) {
  final body = (ByteWriter()..writeUint32(id)).toBytes();
  return connection.exchange<void>(_comStmtClose, body, (reader) async {});
}

/// Runs [attempt], and if it fails with error 1615 (`ER_NEED_REPREPARE`),
/// calls [invalidate] and runs [attempt] exactly one more time.
///
/// Separate from the execution itself, and taking plain callbacks rather
/// than a [MySqlConnection] or a [PreparedStatement] directly, for the same
/// reason [StatementCache] takes injectable `prepare`/`close` functions:
/// this policy cannot be driven at all without something able to produce
/// the error, and 1615 could not be provoked against a real 8.0 or 8.4
/// server by any of eight schema changes tried (adding a column, dropping
/// and recreating the table, changing a column's type, converting the
/// character set, swapping tables with `RENAME TABLE`, `TRUNCATE`, adding
/// an `AUTO_INCREMENT` primary key that shifts column order, and
/// redefining a view) -- the server absorbed every one of them silently.
/// The only way this policy is ever exercised is a test that supplies the
/// error directly, which is exactly what taking [attempt] and [invalidate]
/// as callbacks makes possible.
///
/// A second 1615 right after [invalidate] and a fresh [attempt] is a real
/// failure, not this same recoverable case again, and is not caught a
/// second time -- [attempt] runs at most twice in total.
Future<T> withReprepareRetry<T>(
  Future<T> Function() attempt,
  void Function() invalidate,
) async {
  try {
    return await attempt();
  } on MySqlException catch (e) {
    if (e.errorCode != _erNeedReprepare) {
      rethrow;
    }
    invalidate();
    return await attempt();
  }
}

/// Runs [statement] against [connection] with [values] bound to its
/// placeholders, in order, and reads every result set the reply carries.
///
/// Composes [withReprepareRetry] with [MySqlConnection.statements]: on
/// error 1615, the stale cache entry for [PreparedStatement.sql] is
/// invalidated and [attempt] is run again, which re-resolves the current
/// statement for that SQL text from the cache -- a fresh prepare, since
/// the stale entry was just dropped -- rather than retrying the same
/// invalid statement id a second time. Only possible when
/// [PreparedStatement.sql] is known; a statement built directly rather
/// than through the cache has no SQL text to re-prepare from, so it is run
/// once, plainly, and any error -- 1615 included -- simply propagates.
///
/// [statement] is advisory rather than authoritative whenever its `sql`
/// is known: every attempt, not only a retry, re-resolves the statement
/// to run from [MySqlConnection.statements] by that text, rather than
/// executing the object passed in directly. This is deliberate:
/// [PreparedStatement.sql] is only ever set by the cache itself (see
/// [statementCacheFor]), so a caller holding one with a non-null `sql`
/// already got it from there, and the lookup is always a cache hit
/// returning that identical object back -- harmless in the ordinary
/// case, but worth naming, because it does mean this function cannot be
/// used to force a specific, possibly-stale [PreparedStatement] to run:
/// the SQL text is what is authoritative, and whatever the cache
/// currently holds for it is what actually executes.
Future<MySqlResultSets> executeStatement(
  MySqlConnection connection,
  PreparedStatement statement,
  List<Object?> values,
) {
  if (values.length != statement.parameterCount) {
    throw ArgumentError(
      'statement expects ${statement.parameterCount} parameter(s) but got '
      '${values.length}',
    );
  }

  final sql = statement.sql;
  if (sql == null) {
    return _executeOnce(connection, statement, values);
  }

  return withReprepareRetry(() async {
    final current = await connection.statements.get(sql);
    return _executeOnce(connection, current, values);
  }, () => connection.statements.invalidate(sql));
}

Future<MySqlResultSets> _executeOnce(
  MySqlConnection connection,
  PreparedStatement statement,
  List<Object?> values,
) {
  final payload = buildExecutePayload(statement, values);
  return connection.exchange<MySqlResultSets>(
    _comStmtExecute,
    payload,
    (reader) => _readResultSets(reader, decodeBinaryRow),
  );
}

/// Builds a `COM_STMT_EXECUTE` payload for [statement] with [values] bound
/// to its placeholders, in order.
///
/// Layout:
/// ```
/// int4 statement_id | int1 flags(0x00) | int4 iteration_count(1)
/// if statement.parameterCount > 0:
///   NULL bitmap ((parameterCount + 7) ~/ 8 bytes)
///   int1 new_params_bound_flag(1)
///   parameterCount * (int1 type, int1 unsigned flag) -- unsigned is 0x80
///   the value of every non-NULL parameter, in order
/// ```
///
/// Public (though not exported from the package barrel) specifically so
/// the NULL bitmap's lack of an offset -- the single most easily
/// transposed detail in this file, see the comment on it below -- has its
/// own byte-level unit tests that run on every `dart test`, not only
/// under the `integration` tag this repository skips by default.
Uint8List buildExecutePayload(
  PreparedStatement statement,
  List<Object?> values,
) {
  final writer = ByteWriter()
    ..writeUint32(statement.id)
    ..writeUint8(0x00) // flags: no cursor.
    ..writeUint32(1); // iteration_count: always 1.

  if (statement.parameterCount == 0) {
    return writer.toBytes();
  }

  final encoded = [for (final value in values) encodeParameter(value)];

  // This NULL bitmap starts at bit 0: parameter i's bit is bit i, with no
  // offset. That is a *different* rule from the NULL bitmap in a result
  // row (see decodeBinaryRow), which reserves its first 2 bits and so
  // starts column i's bit at i + 2. The two are unrelated bitmaps that
  // happen to share a name -- this one's offset is absent on purpose, not
  // an oversight, and it must not be merged with the row one into a single
  // helper.
  final bitmap = Uint8List((statement.parameterCount + 7) ~/ 8);
  for (var i = 0; i < values.length; i++) {
    if (values[i] == null) {
      bitmap[i ~/ 8] |= 1 << (i % 8);
    }
  }
  writer.writeBytes(bitmap);

  writer.writeUint8(1); // new_params_bound_flag: always resend types.
  for (final parameter in encoded) {
    writer.writeUint8(parameter.type);
    writer.writeUint8(parameter.unsigned ? 0x80 : 0x00);
  }
  for (var i = 0; i < values.length; i++) {
    if (values[i] != null) {
      writer.writeBytes(encoded[i].bytes);
    }
  }

  return writer.toBytes();
}

/// Reads every result set a `COM_QUERY` reply carries, decoding each row
/// as [String] or `null`. See [MySqlConnection.runTextQuery].
Future<MySqlResultSets> readTextResultSets(ResponseReader reader) =>
    _readResultSets(reader, _decodeTextRow);

/// Decodes one text-protocol row: a length-encoded string, or the
/// length-encoded-integer NULL marker, per column -- no leading marker
/// byte and no NULL bitmap, unlike a binary-protocol row (see
/// [decodeBinaryRow]).
///
/// Every value comes back as a [String] or `null`, never as a typed Dart
/// value: [MySqlConnection.runTextQuery] exists for statements that cannot
/// be prepared at all (`CREATE PROCEDURE`, `SET SESSION`, ...), not for
/// reading application data, so there is no per-column type to decode
/// against in the first place. [columns] is only consulted for its
/// length, to know how many values the row holds.
List<Object?> _decodeTextRow(
  Uint8List payload,
  List<ColumnDefinition> columns,
) {
  final reader = ByteReader(payload);
  return [
    for (var i = 0; i < columns.length; i++) reader.readLengthEncodedString(),
  ];
}

/// Reads every result set an already-sent command's reply carries,
/// decoding each row with [decodeRow] -- [decodeBinaryRow] for
/// [executeStatement]'s binary rows, [_decodeTextRow] for
/// [readTextResultSets]'s text ones.
///
/// Loops for as long as the packet ending each result set has
/// [_serverMoreResultsExists] set: `CALL`ing a procedure that runs several
/// `SELECT`s produces one result set per statement, and this protocol has
/// no resynchronisation point, so leaving even one of them unread would
/// desynchronise the connection for good -- every later read on it would
/// see these leftovers instead of that read's own answer.
Future<MySqlResultSets> _readResultSets(
  ResponseReader reader,
  List<Object?> Function(Uint8List, List<ColumnDefinition>) decodeRow,
) async {
  final sets = <MySqlResult>[];
  while (true) {
    final first = parseCommandPacket(await reader.next());
    switch (first) {
      case ErrPacket err:
        throw mysqlErrorFor(err);

      case OkPacket ok:
        sets.add(
          MySqlResult(
            columns: const [],
            rows: const [],
            affectedRows: ok.affectedRows,
            lastInsertId: ok.lastInsertId,
            moreResults: ok.statusFlags & _serverMoreResultsExists != 0,
          ),
        );

      case ResultSetHeader(columnCount: final columnCount):
        final columns = [
          for (var i = 0; i < columnCount; i++)
            parseColumnDefinition(await reader.next()),
        ];
        final read = await _readRows(reader, columns, decodeRow);
        sets.add(
          MySqlResult(
            columns: columns,
            rows: read.rows,
            affectedRows: 0,
            lastInsertId: 0,
            moreResults:
                read.terminator.statusFlags & _serverMoreResultsExists != 0,
          ),
        );

      case EofPacket():
      case AuthSwitchRequest():
      case AuthMoreData():
        throw MySqlProtocolException(
          'expected OK, ERR or a result set header while reading a '
          'result set, got a ${first.runtimeType}',
        );
    }

    if (!sets.last.moreResults) {
      return MySqlResultSets(sets);
    }
  }
}

/// Whether [raw] is the packet that ends a result set: an error (`0xff`),
/// or the deprecated-EOF OK that ends it cleanly (`0xfe`, under 9 bytes
/// total). Everything else is a row, in either protocol this is used for.
///
/// A length-encoded value never starts with `0xff` -- that byte is
/// reserved for an ERR packet -- and the `0xfe` extended-length form alone
/// takes 9 bytes (a marker plus an 8-byte length) before a single byte of
/// actual data, so a packet under 9 bytes using it cannot be a row either.
/// Every other leading byte, including `0x00` (an empty first value in a
/// text row, or a binary row's fixed header byte) and `0xfb` (a NULL first
/// value in a text row), is ordinary row content here.
///
/// This is deliberately not [parseCommandPacket], which treats `0x00` as
/// OK and `0xfb` as a LOCAL INFILE request unconditionally: both those
/// readings are only correct for the very first packet of a whole reply,
/// never for one already inside an established result set, where a row
/// can legitimately start with either byte.
bool _endsResultSet(Uint8List raw) =>
    raw.isNotEmpty && (raw[0] == 0xff || (raw[0] == 0xfe && raw.length < 9));

/// One result set's rows, decoded with [decodeRow], plus the packet that
/// ended it. Shared between the binary rows [executeStatement] reads and
/// the text rows [readTextResultSets] reads; only [decodeRow] differs
/// between the two.
Future<({List<List<Object?>> rows, OkPacket terminator})> _readRows(
  ResponseReader reader,
  List<ColumnDefinition> columns,
  List<Object?> Function(Uint8List, List<ColumnDefinition>) decodeRow,
) async {
  final rows = <List<Object?>>[];
  while (true) {
    final raw = await reader.next();
    if (!_endsResultSet(raw)) {
      rows.add(decodeRow(raw, columns));
      continue;
    }
    final packet = parseCommandPacket(raw);
    if (packet is OkPacket) {
      return (rows: rows, terminator: packet);
    }
    if (packet is ErrPacket) {
      throw mysqlErrorFor(packet);
    }
    throw MySqlProtocolException(
      'expected a row or OK ending a result set, got a '
      '${packet.runtimeType}',
    );
  }
}
