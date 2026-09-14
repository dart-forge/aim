// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'input.dart';

// **************************************************************************
// RecordPgTableGenerator
// **************************************************************************

extension PostgresUsersDatabaseX on PostgresDatabase {
  UsersQueryBuilder get users => UsersQueryBuilder(this);
}

extension PostgresUsersTransactionX on PostgresTransaction {
  UsersQueryBuilder get users => UsersQueryBuilder(this);
}

// Query Builder for table: users
class UsersQueryBuilder {
  final PostgresQueryable db;

  UsersQueryBuilder(this.db);

  UsersSelectBuilder select() {
    return UsersSelectBuilder(
      db,
      UsersSelectConfig(where: null, limit: null, offset: null),
    );
  }

  UsersInsertBuilder insert() {
    return UsersInsertBuilder(db);
  }

  UsersUpdateBuilder update() {
    return UsersUpdateBuilder(db);
  }

  UsersDeleteBuilder delete() {
    return UsersDeleteBuilder(db);
  }
}

typedef UsersRow = ({String id, String name, DateTime createdAt});

class UsersSelectBuilder extends QueryFuture<List<UsersRow>>
    with FutureMixin<List<UsersRow>> {
  final PostgresQueryable db;
  final UsersSelectConfig config;

  UsersSelectBuilder(this.db, this.config);

  @override
  Future<List<UsersRow>> execute() {
    final sqlBuffer = StringBuffer('SELECT * FROM users');
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
          name: row['name'] as String,
          createdAt: row['created_at'] as DateTime,
        );
      }).toList();
    });
  }

  UsersSelectBuilder where({
    Condition? id,
    Condition? name,
    Condition? createdAt,
  }) {
    final newConditions = [...config.where];
    if (id != null) newConditions.add(id);
    if (name != null) newConditions.add(name);
    if (createdAt != null) newConditions.add(createdAt);

    return UsersSelectBuilder(
      db,
      UsersSelectConfig(
        where: newConditions,
        limit: config.limit,
        offset: config.offset,
      ),
    );
  }

  UsersSelectBuilder limit(int limit) {
    return UsersSelectBuilder(
      db,
      UsersSelectConfig(
        where: config.where,
        limit: limit,
        offset: config.offset,
      ),
    );
  }

  UsersSelectBuilder offset(int offset) {
    return UsersSelectBuilder(
      db,
      UsersSelectConfig(
        where: config.where,
        limit: config.limit,
        offset: offset,
      ),
    );
  }
}

class UsersSelectConfig {
  final List<Condition> where;
  final int? limit;
  final int? offset;

  UsersSelectConfig({
    required List<Condition>? where,
    required this.limit,
    required this.offset,
  }) : where = where ?? [];

  @override
  String toString() {
    return 'UsersSelectConfig(where: $where, limit: $limit, offset: $offset)';
  }
}

class UsersInsertBuilder extends QueryFuture<int> with FutureMixin<int> {
  final PostgresQueryable db;
  final String? _id;
  final String? _name;
  final DateTime? _createdAt;

  UsersInsertBuilder(this.db, {String? id, String? name, DateTime? createdAt})
    : _id = id,
      _name = name,
      _createdAt = createdAt;

  UsersInsertBuilder values({
    required String id,
    required String name,
    required DateTime createdAt,
  }) {
    return UsersInsertBuilder(db, id: id, name: name, createdAt: createdAt);
  }

  @override
  Future<int> execute() {
    if (_id == null) {
      throw StateError('Field `id` is required but not set');
    }
    if (_name == null) {
      throw StateError('Field `name` is required but not set');
    }
    if (_createdAt == null) {
      throw StateError('Field `createdAt` is required but not set');
    }
    final sql =
        'INSERT INTO users (id, name, created_at) VALUES (:id, :name, :created_at)';
    final params = {'id': _id, 'name': _name, 'created_at': _createdAt};
    return db.execute(sql, params: params);
  }
}

class UsersUpdateBuilder extends QueryFuture<int> with FutureMixin<int> {
  final PostgresQueryable db;
  final String? _id;
  final String? _name;
  final DateTime? _createdAt;
  final List<Condition> _where;

  UsersUpdateBuilder(
    this.db, {
    String? id,
    String? name,
    DateTime? createdAt,
    List<Condition>? where,
  }) : _id = id,
       _name = name,
       _createdAt = createdAt,
       _where = where ?? [];

  // SET句（更新するカラムを指定）
  UsersUpdateBuilder set({String? id, String? name, DateTime? createdAt}) {
    return UsersUpdateBuilder(
      db,
      where: _where,
      id: id,
      name: name,
      createdAt: createdAt,
    );
  }

  // WHERE句（SelectBuilderと同じ仕組み）
  UsersUpdateBuilder where({
    Condition? id,
    Condition? name,
    Condition? createdAt,
  }) {
    final newConditions = [..._where];
    if (id != null) newConditions.add(id);
    if (name != null) newConditions.add(name);
    if (createdAt != null) newConditions.add(createdAt);
    return UsersUpdateBuilder(
      db,
      where: newConditions,
      id: _id,
      name: _name,
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
    if (_name != null) {
      updates.add('name = :set_name');
      params['set_name'] = _name;
    }
    if (_createdAt != null) {
      updates.add('created_at = :set_created_at');
      params['set_created_at'] = _createdAt;
    }

    if (updates.isEmpty) throw StateError('No fields to update');

    final sqlBuffer = StringBuffer('UPDATE users SET ${updates.join(', ')}');

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

class UsersDeleteBuilder extends QueryFuture<int> with FutureMixin<int> {
  final PostgresQueryable db;
  final List<Condition> _where;

  UsersDeleteBuilder(this.db, [List<Condition>? where]) : _where = where ?? [];

  // WHERE句（SelectBuilderと同じ仕組み）
  UsersDeleteBuilder where({
    Condition? id,
    Condition? name,
    Condition? createdAt,
  }) {
    final newConditions = [..._where];
    if (id != null) newConditions.add(id);
    if (name != null) newConditions.add(name);
    if (createdAt != null) newConditions.add(createdAt);
    return UsersDeleteBuilder(db, newConditions);
  }

  @override
  Future<int> execute() {
    final sqlBuffer = StringBuffer('DELETE FROM users');
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
