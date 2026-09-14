// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'test.dart';

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

typedef UsersRow = ({
  String id,
  String name,
  String email,
  int? age,
  String? gender,
  DateTime createdAt,
});

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
          email: row['email'] as String,
          age: row['age'] as int?,
          gender: row['gender'] as String?,
          createdAt: row['created_at'] as DateTime,
        );
      }).toList();
    });
  }

  UsersSelectBuilder where({
    Condition? id,
    Condition? name,
    Condition? email,
    Condition? age,
    Condition? gender,
    Condition? createdAt,
  }) {
    final newConditions = [...config.where];
    if (id != null) newConditions.add(id);
    if (name != null) newConditions.add(name);
    if (email != null) newConditions.add(email);
    if (age != null) newConditions.add(age);
    if (gender != null) newConditions.add(gender);
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
  final String? _email;
  final int? _age;
  final String? _gender;
  final DateTime? _createdAt;

  UsersInsertBuilder(
    this.db, {
    String? id,
    String? name,
    String? email,
    int? age,
    String? gender,
    DateTime? createdAt,
  }) : _id = id,
       _name = name,
       _email = email,
       _age = age,
       _gender = gender,
       _createdAt = createdAt;

  UsersInsertBuilder values({
    required String id,
    required String name,
    required String email,
    int? age,
    String? gender,
    required DateTime createdAt,
  }) {
    return UsersInsertBuilder(
      db,
      id: id,
      name: name,
      email: email,
      age: age,
      gender: gender,
      createdAt: createdAt,
    );
  }

  @override
  Future<int> execute() {
    if (_id == null) {
      throw StateError('Field `id` is required but not set');
    }
    if (_name == null) {
      throw StateError('Field `name` is required but not set');
    }
    if (_email == null) {
      throw StateError('Field `email` is required but not set');
    }
    if (_createdAt == null) {
      throw StateError('Field `createdAt` is required but not set');
    }
    final sql =
        'INSERT INTO users (id, name, email, age, gender, created_at) VALUES (:id, :name, :email, :age, :gender, :created_at)';
    final params = {
      'id': _id,
      'name': _name,
      'email': _email,
      'age': _age,
      'gender': _gender,
      'created_at': _createdAt,
    };
    return db.execute(sql, params: params);
  }
}

class UsersUpdateBuilder extends QueryFuture<int> with FutureMixin<int> {
  final PostgresQueryable db;
  final String? _id;
  final String? _name;
  final String? _email;
  final int? _age;
  final String? _gender;
  final DateTime? _createdAt;
  final List<Condition> _where;

  UsersUpdateBuilder(
    this.db, {
    String? id,
    String? name,
    String? email,
    int? age,
    String? gender,
    DateTime? createdAt,
    List<Condition>? where,
  }) : _id = id,
       _name = name,
       _email = email,
       _age = age,
       _gender = gender,
       _createdAt = createdAt,
       _where = where ?? [];

  // SET句（更新するカラムを指定）
  UsersUpdateBuilder set({
    String? id,
    String? name,
    String? email,
    int? age,
    String? gender,
    DateTime? createdAt,
  }) {
    return UsersUpdateBuilder(
      db,
      where: _where,
      id: id,
      name: name,
      email: email,
      age: age,
      gender: gender,
      createdAt: createdAt,
    );
  }

  // WHERE句（SelectBuilderと同じ仕組み）
  UsersUpdateBuilder where({
    Condition? id,
    Condition? name,
    Condition? email,
    Condition? age,
    Condition? gender,
    Condition? createdAt,
  }) {
    final newConditions = [..._where];
    if (id != null) newConditions.add(id);
    if (name != null) newConditions.add(name);
    if (email != null) newConditions.add(email);
    if (age != null) newConditions.add(age);
    if (gender != null) newConditions.add(gender);
    if (createdAt != null) newConditions.add(createdAt);
    return UsersUpdateBuilder(
      db,
      where: newConditions,
      id: _id,
      name: _name,
      email: _email,
      age: _age,
      gender: _gender,
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
    if (_email != null) {
      updates.add('email = :set_email');
      params['set_email'] = _email;
    }
    if (_age != null) {
      updates.add('age = :set_age');
      params['set_age'] = _age;
    }
    if (_gender != null) {
      updates.add('gender = :set_gender');
      params['set_gender'] = _gender;
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
    Condition? email,
    Condition? age,
    Condition? gender,
    Condition? createdAt,
  }) {
    final newConditions = [..._where];
    if (id != null) newConditions.add(id);
    if (name != null) newConditions.add(name);
    if (email != null) newConditions.add(email);
    if (age != null) newConditions.add(age);
    if (gender != null) newConditions.add(gender);
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

extension PostgresPostsDatabaseX on PostgresDatabase {
  PostsQueryBuilder get posts => PostsQueryBuilder(this);
}

extension PostgresPostsTransactionX on PostgresTransaction {
  PostsQueryBuilder get posts => PostsQueryBuilder(this);
}

// Query Builder for table: posts
class PostsQueryBuilder {
  final PostgresQueryable db;

  PostsQueryBuilder(this.db);

  PostsSelectBuilder select() {
    return PostsSelectBuilder(
      db,
      PostsSelectConfig(where: null, limit: null, offset: null),
    );
  }

  PostsInsertBuilder insert() {
    return PostsInsertBuilder(db);
  }

  PostsUpdateBuilder update() {
    return PostsUpdateBuilder(db);
  }

  PostsDeleteBuilder delete() {
    return PostsDeleteBuilder(db);
  }
}

typedef PostsRow = ({
  String id,
  String userId,
  String title,
  String content,
  DateTime createdAt,
  String statusId,
});

class PostsSelectBuilder extends QueryFuture<List<PostsRow>>
    with FutureMixin<List<PostsRow>> {
  final PostgresQueryable db;
  final PostsSelectConfig config;

  PostsSelectBuilder(this.db, this.config);

  @override
  Future<List<PostsRow>> execute() {
    final sqlBuffer = StringBuffer('SELECT * FROM posts');
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
          userId: row['user_id'] as String,
          title: row['title'] as String,
          content: row['content'] as String,
          createdAt: row['created_at'] as DateTime,
          statusId: row['status_id'] as String,
        );
      }).toList();
    });
  }

  PostsWithUserSelectBuilder withUser() {
    return PostsWithUserSelectBuilder(
      db,
      PostsWithUserSelectConfig(
        where: config.where,
        limit: config.limit,
        offset: config.offset,
      ),
    );
  }

  PostsWithStatusSelectBuilder withStatus() {
    return PostsWithStatusSelectBuilder(
      db,
      PostsWithStatusSelectConfig(
        where: config.where,
        limit: config.limit,
        offset: config.offset,
      ),
    );
  }

  PostsSelectBuilder where({
    Condition? id,
    Condition? userId,
    Condition? title,
    Condition? content,
    Condition? createdAt,
    Condition? statusId,
  }) {
    final newConditions = [...config.where];
    if (id != null) newConditions.add(id);
    if (userId != null) newConditions.add(userId);
    if (title != null) newConditions.add(title);
    if (content != null) newConditions.add(content);
    if (createdAt != null) newConditions.add(createdAt);
    if (statusId != null) newConditions.add(statusId);

    return PostsSelectBuilder(
      db,
      PostsSelectConfig(
        where: newConditions,
        limit: config.limit,
        offset: config.offset,
      ),
    );
  }

  PostsSelectBuilder limit(int limit) {
    return PostsSelectBuilder(
      db,
      PostsSelectConfig(
        where: config.where,
        limit: limit,
        offset: config.offset,
      ),
    );
  }

  PostsSelectBuilder offset(int offset) {
    return PostsSelectBuilder(
      db,
      PostsSelectConfig(
        where: config.where,
        limit: config.limit,
        offset: offset,
      ),
    );
  }
}

class PostsSelectConfig {
  final List<Condition> where;
  final int? limit;
  final int? offset;

  PostsSelectConfig({
    required List<Condition>? where,
    required this.limit,
    required this.offset,
  }) : where = where ?? [];

  @override
  String toString() {
    return 'PostsSelectConfig(where: $where, limit: $limit, offset: $offset)';
  }
}

class PostsInsertBuilder extends QueryFuture<int> with FutureMixin<int> {
  final PostgresQueryable db;
  final String? _id;
  final String? _userId;
  final String? _title;
  final String? _content;
  final DateTime? _createdAt;
  final String? _statusId;

  PostsInsertBuilder(
    this.db, {
    String? id,
    String? userId,
    String? title,
    String? content,
    DateTime? createdAt,
    String? statusId,
  }) : _id = id,
       _userId = userId,
       _title = title,
       _content = content,
       _createdAt = createdAt,
       _statusId = statusId;

  PostsInsertBuilder values({
    required String id,
    required String userId,
    required String title,
    required String content,
    required DateTime createdAt,
    required String statusId,
  }) {
    return PostsInsertBuilder(
      db,
      id: id,
      userId: userId,
      title: title,
      content: content,
      createdAt: createdAt,
      statusId: statusId,
    );
  }

  @override
  Future<int> execute() {
    if (_id == null) {
      throw StateError('Field `id` is required but not set');
    }
    if (_userId == null) {
      throw StateError('Field `userId` is required but not set');
    }
    if (_title == null) {
      throw StateError('Field `title` is required but not set');
    }
    if (_content == null) {
      throw StateError('Field `content` is required but not set');
    }
    if (_createdAt == null) {
      throw StateError('Field `createdAt` is required but not set');
    }
    if (_statusId == null) {
      throw StateError('Field `statusId` is required but not set');
    }
    final sql =
        'INSERT INTO posts (id, user_id, title, content, created_at, status_id) VALUES (:id, :user_id, :title, :content, :created_at, :status_id)';
    final params = {
      'id': _id,
      'user_id': _userId,
      'title': _title,
      'content': _content,
      'created_at': _createdAt,
      'status_id': _statusId,
    };
    return db.execute(sql, params: params);
  }
}

class PostsUpdateBuilder extends QueryFuture<int> with FutureMixin<int> {
  final PostgresQueryable db;
  final String? _id;
  final String? _userId;
  final String? _title;
  final String? _content;
  final DateTime? _createdAt;
  final String? _statusId;
  final List<Condition> _where;

  PostsUpdateBuilder(
    this.db, {
    String? id,
    String? userId,
    String? title,
    String? content,
    DateTime? createdAt,
    String? statusId,
    List<Condition>? where,
  }) : _id = id,
       _userId = userId,
       _title = title,
       _content = content,
       _createdAt = createdAt,
       _statusId = statusId,
       _where = where ?? [];

  // SET句（更新するカラムを指定）
  PostsUpdateBuilder set({
    String? id,
    String? userId,
    String? title,
    String? content,
    DateTime? createdAt,
    String? statusId,
  }) {
    return PostsUpdateBuilder(
      db,
      where: _where,
      id: id,
      userId: userId,
      title: title,
      content: content,
      createdAt: createdAt,
      statusId: statusId,
    );
  }

  // WHERE句（SelectBuilderと同じ仕組み）
  PostsUpdateBuilder where({
    Condition? id,
    Condition? userId,
    Condition? title,
    Condition? content,
    Condition? createdAt,
    Condition? statusId,
  }) {
    final newConditions = [..._where];
    if (id != null) newConditions.add(id);
    if (userId != null) newConditions.add(userId);
    if (title != null) newConditions.add(title);
    if (content != null) newConditions.add(content);
    if (createdAt != null) newConditions.add(createdAt);
    if (statusId != null) newConditions.add(statusId);
    return PostsUpdateBuilder(
      db,
      where: newConditions,
      id: _id,
      userId: _userId,
      title: _title,
      content: _content,
      createdAt: _createdAt,
      statusId: _statusId,
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
    if (_userId != null) {
      updates.add('user_id = :set_user_id');
      params['set_user_id'] = _userId;
    }
    if (_title != null) {
      updates.add('title = :set_title');
      params['set_title'] = _title;
    }
    if (_content != null) {
      updates.add('content = :set_content');
      params['set_content'] = _content;
    }
    if (_createdAt != null) {
      updates.add('created_at = :set_created_at');
      params['set_created_at'] = _createdAt;
    }
    if (_statusId != null) {
      updates.add('status_id = :set_status_id');
      params['set_status_id'] = _statusId;
    }

    if (updates.isEmpty) throw StateError('No fields to update');

    final sqlBuffer = StringBuffer('UPDATE posts SET ${updates.join(', ')}');

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

class PostsDeleteBuilder extends QueryFuture<int> with FutureMixin<int> {
  final PostgresQueryable db;
  final List<Condition> _where;

  PostsDeleteBuilder(this.db, [List<Condition>? where]) : _where = where ?? [];

  // WHERE句（SelectBuilderと同じ仕組み）
  PostsDeleteBuilder where({
    Condition? id,
    Condition? userId,
    Condition? title,
    Condition? content,
    Condition? createdAt,
    Condition? statusId,
  }) {
    final newConditions = [..._where];
    if (id != null) newConditions.add(id);
    if (userId != null) newConditions.add(userId);
    if (title != null) newConditions.add(title);
    if (content != null) newConditions.add(content);
    if (createdAt != null) newConditions.add(createdAt);
    if (statusId != null) newConditions.add(statusId);
    return PostsDeleteBuilder(db, newConditions);
  }

  @override
  Future<int> execute() {
    final sqlBuffer = StringBuffer('DELETE FROM posts');
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

typedef PostsWithUserRow = ({PostsRow post, UsersRow user});

class PostsWithUserSelectConfig {
  final List<Condition> where;
  final int? limit;
  final int? offset;

  PostsWithUserSelectConfig({
    required List<Condition>? where,
    required this.limit,
    required this.offset,
  }) : where = where ?? [];
}

class PostsWithUserSelectBuilder extends QueryFuture<List<PostsWithUserRow>>
    with FutureMixin<List<PostsWithUserRow>> {
  final PostgresQueryable db;
  final PostsWithUserSelectConfig config;

  PostsWithUserSelectBuilder(this.db, this.config);

  @override
  Future<List<PostsWithUserRow>> execute() {
    final sqlBuffer = StringBuffer(
      'SELECT posts.id AS posts_id, posts.user_id AS posts_user_id, posts.title AS posts_title, posts.content AS posts_content, posts.created_at AS posts_created_at, posts.status_id AS posts_status_id, users.id AS users_id, users.name AS users_name, users.email AS users_email, users.age AS users_age, users.gender AS users_gender, users.created_at AS users_created_at FROM posts',
    );
    sqlBuffer.write(' INNER JOIN users ON posts.user_id = users.id');
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
    return db.query(sqlBuffer.toString(), params: params).then((result) {
      return result.map((row) {
        return (
          post: (
            id: row['posts_id'] as String,
            userId: row['posts_user_id'] as String,
            title: row['posts_title'] as String,
            content: row['posts_content'] as String,
            createdAt: row['posts_created_at'] as DateTime,
            statusId: row['posts_status_id'] as String,
          ),
          user: (
            id: row['users_id'] as String,
            name: row['users_name'] as String,
            email: row['users_email'] as String,
            age: row['users_age'] as int?,
            gender: row['users_gender'] as String?,
            createdAt: row['users_created_at'] as DateTime,
          ),
        );
      }).toList();
    });
  }

  PostsWithUserWithStatusSelectBuilder withStatus() {
    return PostsWithUserWithStatusSelectBuilder(
      db,
      PostsWithUserWithStatusSelectConfig(
        where: config.where,
        limit: config.limit,
        offset: config.offset,
      ),
    );
  }

  PostsWithUserSelectBuilder where({
    Condition? id,
    Condition? userId,
    Condition? title,
    Condition? content,
    Condition? createdAt,
    Condition? statusId,
  }) {
    final newConditions = [...config.where];
    if (id != null) newConditions.add(id);
    if (userId != null) newConditions.add(userId);
    if (title != null) newConditions.add(title);
    if (content != null) newConditions.add(content);
    if (createdAt != null) newConditions.add(createdAt);
    if (statusId != null) newConditions.add(statusId);
    return PostsWithUserSelectBuilder(
      db,
      PostsWithUserSelectConfig(
        where: newConditions,
        limit: config.limit,
        offset: config.offset,
      ),
    );
  }

  PostsWithUserSelectBuilder limit(int limit) {
    return PostsWithUserSelectBuilder(
      db,
      PostsWithUserSelectConfig(
        where: config.where,
        limit: limit,
        offset: config.offset,
      ),
    );
  }

  PostsWithUserSelectBuilder offset(int offset) {
    return PostsWithUserSelectBuilder(
      db,
      PostsWithUserSelectConfig(
        where: config.where,
        limit: config.limit,
        offset: offset,
      ),
    );
  }
}

typedef PostsWithStatusRow = ({PostsRow post, StatusRow status});

class PostsWithStatusSelectConfig {
  final List<Condition> where;
  final int? limit;
  final int? offset;

  PostsWithStatusSelectConfig({
    required List<Condition>? where,
    required this.limit,
    required this.offset,
  }) : where = where ?? [];
}

class PostsWithStatusSelectBuilder extends QueryFuture<List<PostsWithStatusRow>>
    with FutureMixin<List<PostsWithStatusRow>> {
  final PostgresQueryable db;
  final PostsWithStatusSelectConfig config;

  PostsWithStatusSelectBuilder(this.db, this.config);

  @override
  Future<List<PostsWithStatusRow>> execute() {
    final sqlBuffer = StringBuffer(
      'SELECT posts.id AS posts_id, posts.user_id AS posts_user_id, posts.title AS posts_title, posts.content AS posts_content, posts.created_at AS posts_created_at, posts.status_id AS posts_status_id, status.id AS status_id, status.description AS status_description, status.created_at AS status_created_at FROM posts',
    );
    sqlBuffer.write(' INNER JOIN status ON posts.status_id = status.id');
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
    return db.query(sqlBuffer.toString(), params: params).then((result) {
      return result.map((row) {
        return (
          post: (
            id: row['posts_id'] as String,
            userId: row['posts_user_id'] as String,
            title: row['posts_title'] as String,
            content: row['posts_content'] as String,
            createdAt: row['posts_created_at'] as DateTime,
            statusId: row['posts_status_id'] as String,
          ),
          status: (
            id: row['status_id'] as String,
            description: row['status_description'] as String,
            createdAt: row['status_created_at'] as DateTime,
          ),
        );
      }).toList();
    });
  }

  PostsWithUserWithStatusSelectBuilder withUser() {
    return PostsWithUserWithStatusSelectBuilder(
      db,
      PostsWithUserWithStatusSelectConfig(
        where: config.where,
        limit: config.limit,
        offset: config.offset,
      ),
    );
  }

  PostsWithStatusSelectBuilder where({
    Condition? id,
    Condition? userId,
    Condition? title,
    Condition? content,
    Condition? createdAt,
    Condition? statusId,
  }) {
    final newConditions = [...config.where];
    if (id != null) newConditions.add(id);
    if (userId != null) newConditions.add(userId);
    if (title != null) newConditions.add(title);
    if (content != null) newConditions.add(content);
    if (createdAt != null) newConditions.add(createdAt);
    if (statusId != null) newConditions.add(statusId);
    return PostsWithStatusSelectBuilder(
      db,
      PostsWithStatusSelectConfig(
        where: newConditions,
        limit: config.limit,
        offset: config.offset,
      ),
    );
  }

  PostsWithStatusSelectBuilder limit(int limit) {
    return PostsWithStatusSelectBuilder(
      db,
      PostsWithStatusSelectConfig(
        where: config.where,
        limit: limit,
        offset: config.offset,
      ),
    );
  }

  PostsWithStatusSelectBuilder offset(int offset) {
    return PostsWithStatusSelectBuilder(
      db,
      PostsWithStatusSelectConfig(
        where: config.where,
        limit: config.limit,
        offset: offset,
      ),
    );
  }
}

typedef PostsWithUserWithStatusRow = ({
  PostsRow post,
  UsersRow user,
  StatusRow status,
});

class PostsWithUserWithStatusSelectConfig {
  final List<Condition> where;
  final int? limit;
  final int? offset;

  PostsWithUserWithStatusSelectConfig({
    required List<Condition>? where,
    required this.limit,
    required this.offset,
  }) : where = where ?? [];
}

class PostsWithUserWithStatusSelectBuilder
    extends QueryFuture<List<PostsWithUserWithStatusRow>>
    with FutureMixin<List<PostsWithUserWithStatusRow>> {
  final PostgresQueryable db;
  final PostsWithUserWithStatusSelectConfig config;

  PostsWithUserWithStatusSelectBuilder(this.db, this.config);

  @override
  Future<List<PostsWithUserWithStatusRow>> execute() {
    final sqlBuffer = StringBuffer(
      'SELECT posts.id AS posts_id, posts.user_id AS posts_user_id, posts.title AS posts_title, posts.content AS posts_content, posts.created_at AS posts_created_at, posts.status_id AS posts_status_id, users.id AS users_id, users.name AS users_name, users.email AS users_email, users.age AS users_age, users.gender AS users_gender, users.created_at AS users_created_at, status.id AS status_id, status.description AS status_description, status.created_at AS status_created_at FROM posts',
    );
    sqlBuffer.write(' INNER JOIN users ON posts.user_id = users.id');
    sqlBuffer.write(' INNER JOIN status ON posts.status_id = status.id');
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
    return db.query(sqlBuffer.toString(), params: params).then((result) {
      return result.map((row) {
        return (
          post: (
            id: row['posts_id'] as String,
            userId: row['posts_user_id'] as String,
            title: row['posts_title'] as String,
            content: row['posts_content'] as String,
            createdAt: row['posts_created_at'] as DateTime,
            statusId: row['posts_status_id'] as String,
          ),
          user: (
            id: row['users_id'] as String,
            name: row['users_name'] as String,
            email: row['users_email'] as String,
            age: row['users_age'] as int?,
            gender: row['users_gender'] as String?,
            createdAt: row['users_created_at'] as DateTime,
          ),
          status: (
            id: row['status_id'] as String,
            description: row['status_description'] as String,
            createdAt: row['status_created_at'] as DateTime,
          ),
        );
      }).toList();
    });
  }

  PostsWithUserWithStatusSelectBuilder where({
    Condition? id,
    Condition? userId,
    Condition? title,
    Condition? content,
    Condition? createdAt,
    Condition? statusId,
  }) {
    final newConditions = [...config.where];
    if (id != null) newConditions.add(id);
    if (userId != null) newConditions.add(userId);
    if (title != null) newConditions.add(title);
    if (content != null) newConditions.add(content);
    if (createdAt != null) newConditions.add(createdAt);
    if (statusId != null) newConditions.add(statusId);
    return PostsWithUserWithStatusSelectBuilder(
      db,
      PostsWithUserWithStatusSelectConfig(
        where: newConditions,
        limit: config.limit,
        offset: config.offset,
      ),
    );
  }

  PostsWithUserWithStatusSelectBuilder limit(int limit) {
    return PostsWithUserWithStatusSelectBuilder(
      db,
      PostsWithUserWithStatusSelectConfig(
        where: config.where,
        limit: limit,
        offset: config.offset,
      ),
    );
  }

  PostsWithUserWithStatusSelectBuilder offset(int offset) {
    return PostsWithUserWithStatusSelectBuilder(
      db,
      PostsWithUserWithStatusSelectConfig(
        where: config.where,
        limit: config.limit,
        offset: offset,
      ),
    );
  }
}
