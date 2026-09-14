// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'seed.dart';

// **************************************************************************
// RecordPgTableGenerator
// **************************************************************************

extension PostgresStatusDatabaseX on PostgresDatabase {
  StatusQueryBuilder get status => StatusQueryBuilder(this);
}

extension PostgresStatusTransactionX on PostgresTransaction {
  StatusQueryBuilder get status => StatusQueryBuilder(this);
}

// Query Builder for table: status
class StatusQueryBuilder {
  final PostgresQueryable db;

  StatusQueryBuilder(this.db);

  StatusSelectBuilder select() {
    return StatusSelectBuilder(
      db,
      StatusSelectConfig(where: null, limit: null, offset: null),
    );
  }

  StatusInsertBuilder insert() {
    return StatusInsertBuilder(db);
  }

  StatusUpdateBuilder update() {
    return StatusUpdateBuilder(db);
  }

  StatusDeleteBuilder delete() {
    return StatusDeleteBuilder(db);
  }
}

typedef StatusRow = ({String id, String description, DateTime createdAt});

class StatusSelectBuilder extends QueryFuture<List<StatusRow>>
    with FutureMixin<List<StatusRow>> {
  final PostgresQueryable db;
  final StatusSelectConfig config;

  StatusSelectBuilder(this.db, this.config);

  @override
  Future<List<StatusRow>> execute() {
    final sqlBuffer = StringBuffer('SELECT * FROM status');
    final params = <String, dynamic>{};

    if (config.where.isNotEmpty) {
      sqlBuffer.write(' WHERE ');
      final whereClauses = <String>[];

      for (var i = 0; i < config.where.length; i++) {
        final condition = config.where[i];
        whereClauses.add(condition.toSql(i));
        params.addAll(condition.toParams(i));
      }

      sqlBuffer.write(whereClauses.join(' AND '));
    }

    if (config.limit != null) {
      sqlBuffer.write(' LIMIT ${config.limit}');
    }

    if (config.offset != null) {
      sqlBuffer.write(' OFFSET ${config.offset}');
    }

    final sql = sqlBuffer.toString();
    return db.query(sql, params: params).then((result) {
      return result.map((row) {
        return (
          id: row['id'] as String,
          description: row['description'] as String,
          createdAt: row['created_at'] as DateTime,
        );
      }).toList();
    });
  }

  StatusSelectBuilder where({
    Condition? id,
    Condition? description,
    Condition? createdAt,
  }) {
    final newConditions = [...config.where];
    if (id != null) newConditions.add(id);
    if (description != null) newConditions.add(description);
    if (createdAt != null) newConditions.add(createdAt);

    return StatusSelectBuilder(
      db,
      StatusSelectConfig(
        where: newConditions,
        limit: config.limit,
        offset: config.offset,
      ),
    );
  }

  StatusSelectBuilder limit(int limit) {
    return StatusSelectBuilder(
      db,
      StatusSelectConfig(
        where: config.where,
        limit: limit,
        offset: config.offset,
      ),
    );
  }

  StatusSelectBuilder offset(int offset) {
    return StatusSelectBuilder(
      db,
      StatusSelectConfig(
        where: config.where,
        limit: config.limit,
        offset: offset,
      ),
    );
  }
}

class StatusSelectConfig {
  final List<Condition> where;
  final int? limit;
  final int? offset;

  StatusSelectConfig({
    required List<Condition>? where,
    required this.limit,
    required this.offset,
  }) : where = where ?? [];

  @override
  String toString() {
    return 'StatusSelectConfig(where: $where, limit: $limit, offset: $offset)';
  }
}

class StatusInsertBuilder extends QueryFuture<int> with FutureMixin<int> {
  final PostgresQueryable db;
  final String? _id;
  final String? _description;
  final DateTime? _createdAt;

  StatusInsertBuilder(
    this.db, {
    String? id,
    String? description,
    DateTime? createdAt,
  }) : _id = id,
       _description = description,
       _createdAt = createdAt;

  StatusInsertBuilder values({
    required String id,
    required String description,
    required DateTime createdAt,
  }) {
    return StatusInsertBuilder(
      db,
      id: id,
      description: description,
      createdAt: createdAt,
    );
  }

  @override
  Future<int> execute() {
    if (_id == null) {
      throw StateError('Field `id` is required but not set');
    }
    if (_description == null) {
      throw StateError('Field `description` is required but not set');
    }
    if (_createdAt == null) {
      throw StateError('Field `createdAt` is required but not set');
    }
    final sql =
        'INSERT INTO status (id, description, created_at) VALUES (:id, :description, :created_at)';
    final params = {
      'id': _id,
      'description': _description,
      'created_at': _createdAt,
    };
    return db.execute(sql, params: params);
  }
}

class StatusUpdateBuilder extends QueryFuture<int> with FutureMixin<int> {
  final PostgresQueryable db;
  final String? _id;
  final String? _description;
  final DateTime? _createdAt;
  final List<Condition> _where;

  StatusUpdateBuilder(
    this.db, {
    String? id,
    String? description,
    DateTime? createdAt,
    List<Condition>? where,
  }) : _id = id,
       _description = description,
       _createdAt = createdAt,
       _where = where ?? [];

  // SET句（更新するカラムを指定）
  StatusUpdateBuilder set({
    String? id,
    String? description,
    DateTime? createdAt,
  }) {
    return StatusUpdateBuilder(
      db,
      where: _where,
      id: id,
      description: description,
      createdAt: createdAt,
    );
  }

  // WHERE句（SelectBuilderと同じ仕組み）
  StatusUpdateBuilder where({
    Condition? id,
    Condition? description,
    Condition? createdAt,
  }) {
    final newConditions = [..._where];
    if (id != null) newConditions.add(id);
    if (description != null) newConditions.add(description);
    if (createdAt != null) newConditions.add(createdAt);
    return StatusUpdateBuilder(
      db,
      where: newConditions,
      id: _id,
      description: _description,
      createdAt: _createdAt,
    );
  }

  @override
  Future<int> execute() {
    // SET句の構築
    final updates = <String>[];
    final params = <String, dynamic>{};
    if (_id != null) {
      updates.add('id = :set_id');
      params['set_id'] = _id;
    }
    if (_description != null) {
      updates.add('description = :set_description');
      params['set_description'] = _description;
    }
    if (_createdAt != null) {
      updates.add('created_at = :set_created_at');
      params['set_created_at'] = _createdAt;
    }

    if (updates.isEmpty) throw StateError('No fields to update');

    final sqlBuffer = StringBuffer('UPDATE status SET ${updates.join(', ')}');

    // WHERE句の構築
    if (_where.isNotEmpty) {
      sqlBuffer.write(' WHERE ');
      final whereClauses = <String>[];
      for (var i = 0; i < _where.length; i++) {
        final condition = _where[i];
        whereClauses.add(condition.toSql(i));
        params.addAll(condition.toParams(i));
      }
      sqlBuffer.write(whereClauses.join(' AND '));
    }

    return db.execute(sqlBuffer.toString(), params: params);
  }
}

class StatusDeleteBuilder extends QueryFuture<int> with FutureMixin<int> {
  final PostgresQueryable db;
  final List<Condition> _where;

  StatusDeleteBuilder(this.db, [List<Condition>? where]) : _where = where ?? [];

  // WHERE句（SelectBuilderと同じ仕組み）
  StatusDeleteBuilder where({
    Condition? id,
    Condition? description,
    Condition? createdAt,
  }) {
    final newConditions = [..._where];
    if (id != null) newConditions.add(id);
    if (description != null) newConditions.add(description);
    if (createdAt != null) newConditions.add(createdAt);
    return StatusDeleteBuilder(db, newConditions);
  }

  @override
  Future<int> execute() {
    final sqlBuffer = StringBuffer('DELETE FROM status');
    final params = <String, dynamic>{};

    // WHERE句の構築
    if (_where.isNotEmpty) {
      sqlBuffer.write(' WHERE ');
      final whereClauses = <String>[];
      for (var i = 0; i < _where.length; i++) {
        final condition = _where[i];
        whereClauses.add(condition.toSql(i));
        params.addAll(condition.toParams(i));
      }
      sqlBuffer.write(whereClauses.join(' AND '));
    }

    return db.execute(sqlBuffer.toString(), params: params);
  }
}
