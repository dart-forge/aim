import 'package:aim_sqlite/src/types/value_encoder.dart';

/// Sent to a worker isolate.
sealed class SqliteRequest {
  const SqliteRequest(this.id);

  /// Matches a response to its request.
  final int id;
}

class SqliteRunRequest extends SqliteRequest {
  const SqliteRunRequest(
    super.id,
    this.sql, {
    required this.positional,
    required this.named,
    required this.wantRows,
    required this.requireReadOnly,
  });

  final String sql;

  /// Already encoded, so the worker never sees a Dart value it must interpret.
  final List<SqliteBindValue> positional;
  final Map<String, SqliteBindValue> named;

  /// query() wants rows; execute() wants the change count.
  final bool wantRows;

  /// Set for a reader. The worker prepares every statement and refuses the
  /// whole batch if any of them writes.
  final bool requireReadOnly;
}

/// Opens a transaction, which stays open until a commit or a rollback
/// arrives. Nothing else may be sent in between: a statement that reached
/// the connection first would be committed or rolled back along with it.
class SqliteBeginRequest extends SqliteRequest {
  const SqliteBeginRequest(super.id);
}

class SqliteCommitRequest extends SqliteRequest {
  const SqliteCommitRequest(super.id);
}

class SqliteRollbackRequest extends SqliteRequest {
  const SqliteRollbackRequest(super.id);
}

class SqliteCloseRequest extends SqliteRequest {
  const SqliteCloseRequest(super.id);
}

/// Sent back from a worker isolate.
sealed class SqliteResponse {
  const SqliteResponse(this.id);
  final int id;
}

class SqliteRowsResponse extends SqliteResponse {
  const SqliteRowsResponse(super.id, this.rows, this.affected);
  final List<Map<String, Object?>> rows;
  final int affected;
}

/// The batch contains a statement that writes, so it cannot run here.
class SqliteNotReadOnlyResponse extends SqliteResponse {
  const SqliteNotReadOnlyResponse(super.id);
}

class SqliteErrorResponse extends SqliteResponse {
  const SqliteErrorResponse(super.id, this.error);

  /// Rebuilt on the other side. Only sendable types go in here, so this is a
  /// SqliteException, a SqliteDecodeException or an ArgumentError -- all of
  /// which hold nothing but primitives.
  final Object error;
}
