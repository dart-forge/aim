// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tables.dart';

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
  int? age,
  int active,
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
          age: row['age'] as int?,
          active: row['active'] as int,
          createdAt: row['created_at'] as DateTime,
        );
      }).toList();
    });
  }

  UsersSelectBuilder where({
    Condition? id,
    Condition? name,
    Condition? age,
    Condition? active,
    Condition? createdAt,
  }) {
    final newConditions = [...config.where];
    if (id != null) newConditions.add(id);
    if (name != null) newConditions.add(name);
    if (age != null) newConditions.add(age);
    if (active != null) newConditions.add(active);
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
  final int? _age;
  final int? _active;
  final DateTime? _createdAt;

  UsersInsertBuilder(
    this.db, {
    String? id,
    String? name,
    int? age,
    int? active,
    DateTime? createdAt,
  }) : _id = id,
       _name = name,
       _age = age,
       _active = active,
       _createdAt = createdAt;

  UsersInsertBuilder values({
    required String id,
    required String name,
    int? age,
    required int active,
    required DateTime createdAt,
  }) {
    return UsersInsertBuilder(
      db,
      id: id,
      name: name,
      age: age,
      active: active,
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
    if (_active == null) {
      throw StateError('Field `active` is required but not set');
    }
    if (_createdAt == null) {
      throw StateError('Field `createdAt` is required but not set');
    }
    final sql =
        'INSERT INTO users (id, name, age, active, created_at) VALUES (:id, :name, :age, :active, :created_at)';
    final params = {
      'id': _id,
      'name': _name,
      'age': _age,
      'active': _active,
      'created_at': _createdAt,
    };
    return db.execute(sql, params: params);
  }
}

class UsersUpdateBuilder extends QueryFuture<int> with FutureMixin<int> {
  final PostgresQueryable db;
  final String? _id;
  final String? _name;
  final int? _age;
  final int? _active;
  final DateTime? _createdAt;
  final List<Condition> _where;

  UsersUpdateBuilder(
    this.db, {
    String? id,
    String? name,
    int? age,
    int? active,
    DateTime? createdAt,
    List<Condition>? where,
  }) : _id = id,
       _name = name,
       _age = age,
       _active = active,
       _createdAt = createdAt,
       _where = where ?? [];

  // SET句（更新するカラムを指定）
  UsersUpdateBuilder set({
    String? id,
    String? name,
    int? age,
    int? active,
    DateTime? createdAt,
  }) {
    return UsersUpdateBuilder(
      db,
      where: _where,
      id: id,
      name: name,
      age: age,
      active: active,
      createdAt: createdAt,
    );
  }

  // WHERE句（SelectBuilderと同じ仕組み）
  UsersUpdateBuilder where({
    Condition? id,
    Condition? name,
    Condition? age,
    Condition? active,
    Condition? createdAt,
  }) {
    final newConditions = [..._where];
    if (id != null) newConditions.add(id);
    if (name != null) newConditions.add(name);
    if (age != null) newConditions.add(age);
    if (active != null) newConditions.add(active);
    if (createdAt != null) newConditions.add(createdAt);
    return UsersUpdateBuilder(
      db,
      where: newConditions,
      id: _id,
      name: _name,
      age: _age,
      active: _active,
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
    if (_age != null) {
      updates.add('age = :set_age');
      params['set_age'] = _age;
    }
    if (_active != null) {
      updates.add('active = :set_active');
      params['set_active'] = _active;
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
    Condition? age,
    Condition? active,
    Condition? createdAt,
  }) {
    final newConditions = [..._where];
    if (id != null) newConditions.add(id);
    if (name != null) newConditions.add(name);
    if (age != null) newConditions.add(age);
    if (active != null) newConditions.add(active);
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
  String title,
  String content,
  String userId,
  DateTime createdAt,
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
          title: row['title'] as String,
          content: row['content'] as String,
          userId: row['user_id'] as String,
          createdAt: row['created_at'] as DateTime,
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

  PostsSelectBuilder where({
    Condition? id,
    Condition? title,
    Condition? content,
    Condition? userId,
    Condition? createdAt,
  }) {
    final newConditions = [...config.where];
    if (id != null) newConditions.add(id);
    if (title != null) newConditions.add(title);
    if (content != null) newConditions.add(content);
    if (userId != null) newConditions.add(userId);
    if (createdAt != null) newConditions.add(createdAt);

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
  final String? _title;
  final String? _content;
  final String? _userId;
  final DateTime? _createdAt;

  PostsInsertBuilder(
    this.db, {
    String? id,
    String? title,
    String? content,
    String? userId,
    DateTime? createdAt,
  }) : _id = id,
       _title = title,
       _content = content,
       _userId = userId,
       _createdAt = createdAt;

  PostsInsertBuilder values({
    required String id,
    required String title,
    required String content,
    required String userId,
    required DateTime createdAt,
  }) {
    return PostsInsertBuilder(
      db,
      id: id,
      title: title,
      content: content,
      userId: userId,
      createdAt: createdAt,
    );
  }

  @override
  Future<int> execute() {
    if (_id == null) {
      throw StateError('Field `id` is required but not set');
    }
    if (_title == null) {
      throw StateError('Field `title` is required but not set');
    }
    if (_content == null) {
      throw StateError('Field `content` is required but not set');
    }
    if (_userId == null) {
      throw StateError('Field `userId` is required but not set');
    }
    if (_createdAt == null) {
      throw StateError('Field `createdAt` is required but not set');
    }
    final sql =
        'INSERT INTO posts (id, title, content, user_id, created_at) VALUES (:id, :title, :content, :user_id, :created_at)';
    final params = {
      'id': _id,
      'title': _title,
      'content': _content,
      'user_id': _userId,
      'created_at': _createdAt,
    };
    return db.execute(sql, params: params);
  }
}

class PostsUpdateBuilder extends QueryFuture<int> with FutureMixin<int> {
  final PostgresQueryable db;
  final String? _id;
  final String? _title;
  final String? _content;
  final String? _userId;
  final DateTime? _createdAt;
  final List<Condition> _where;

  PostsUpdateBuilder(
    this.db, {
    String? id,
    String? title,
    String? content,
    String? userId,
    DateTime? createdAt,
    List<Condition>? where,
  }) : _id = id,
       _title = title,
       _content = content,
       _userId = userId,
       _createdAt = createdAt,
       _where = where ?? [];

  // SET句（更新するカラムを指定）
  PostsUpdateBuilder set({
    String? id,
    String? title,
    String? content,
    String? userId,
    DateTime? createdAt,
  }) {
    return PostsUpdateBuilder(
      db,
      where: _where,
      id: id,
      title: title,
      content: content,
      userId: userId,
      createdAt: createdAt,
    );
  }

  // WHERE句（SelectBuilderと同じ仕組み）
  PostsUpdateBuilder where({
    Condition? id,
    Condition? title,
    Condition? content,
    Condition? userId,
    Condition? createdAt,
  }) {
    final newConditions = [..._where];
    if (id != null) newConditions.add(id);
    if (title != null) newConditions.add(title);
    if (content != null) newConditions.add(content);
    if (userId != null) newConditions.add(userId);
    if (createdAt != null) newConditions.add(createdAt);
    return PostsUpdateBuilder(
      db,
      where: newConditions,
      id: _id,
      title: _title,
      content: _content,
      userId: _userId,
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
    if (_title != null) {
      updates.add('title = :set_title');
      params['set_title'] = _title;
    }
    if (_content != null) {
      updates.add('content = :set_content');
      params['set_content'] = _content;
    }
    if (_userId != null) {
      updates.add('user_id = :set_user_id');
      params['set_user_id'] = _userId;
    }
    if (_createdAt != null) {
      updates.add('created_at = :set_created_at');
      params['set_created_at'] = _createdAt;
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
    Condition? title,
    Condition? content,
    Condition? userId,
    Condition? createdAt,
  }) {
    final newConditions = [..._where];
    if (id != null) newConditions.add(id);
    if (title != null) newConditions.add(title);
    if (content != null) newConditions.add(content);
    if (userId != null) newConditions.add(userId);
    if (createdAt != null) newConditions.add(createdAt);
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
      'SELECT posts.id AS posts_id, posts.title AS posts_title, posts.content AS posts_content, posts.user_id AS posts_user_id, posts.created_at AS posts_created_at, users.id AS users_id, users.name AS users_name, users.age AS users_age, users.active AS users_active, users.created_at AS users_created_at FROM posts',
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
            title: row['posts_title'] as String,
            content: row['posts_content'] as String,
            userId: row['posts_user_id'] as String,
            createdAt: row['posts_created_at'] as DateTime,
          ),
          user: (
            id: row['users_id'] as String,
            name: row['users_name'] as String,
            age: row['users_age'] as int?,
            active: row['users_active'] as int,
            createdAt: row['users_created_at'] as DateTime,
          ),
        );
      }).toList();
    });
  }

  PostsWithUserSelectBuilder where({
    Condition? id,
    Condition? title,
    Condition? content,
    Condition? userId,
    Condition? createdAt,
  }) {
    final newConditions = [...config.where];
    if (id != null) newConditions.add(id);
    if (title != null) newConditions.add(title);
    if (content != null) newConditions.add(content);
    if (userId != null) newConditions.add(userId);
    if (createdAt != null) newConditions.add(createdAt);
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

extension PostgresArticlesDatabaseX on PostgresDatabase {
  ArticlesQueryBuilder get articles => ArticlesQueryBuilder(this);
}

extension PostgresArticlesTransactionX on PostgresTransaction {
  ArticlesQueryBuilder get articles => ArticlesQueryBuilder(this);
}

// Query Builder for table: articles
class ArticlesQueryBuilder {
  final PostgresQueryable db;

  ArticlesQueryBuilder(this.db);

  ArticlesSelectBuilder select() {
    return ArticlesSelectBuilder(
      db,
      ArticlesSelectConfig(where: null, limit: null, offset: null),
    );
  }

  ArticlesInsertBuilder insert() {
    return ArticlesInsertBuilder(db);
  }

  ArticlesUpdateBuilder update() {
    return ArticlesUpdateBuilder(db);
  }

  ArticlesDeleteBuilder delete() {
    return ArticlesDeleteBuilder(db);
  }
}

typedef ArticlesRow = ({
  String id,
  String title,
  String? authorId,
  DateTime createdAt,
});

class ArticlesSelectBuilder extends QueryFuture<List<ArticlesRow>>
    with FutureMixin<List<ArticlesRow>> {
  final PostgresQueryable db;
  final ArticlesSelectConfig config;

  ArticlesSelectBuilder(this.db, this.config);

  @override
  Future<List<ArticlesRow>> execute() {
    final sqlBuffer = StringBuffer('SELECT * FROM articles');
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
          title: row['title'] as String,
          authorId: row['author_id'] as String?,
          createdAt: row['created_at'] as DateTime,
        );
      }).toList();
    });
  }

  ArticlesWithAuthorSelectBuilder withAuthor() {
    return ArticlesWithAuthorSelectBuilder(
      db,
      ArticlesWithAuthorSelectConfig(
        where: config.where,
        limit: config.limit,
        offset: config.offset,
      ),
    );
  }

  ArticlesSelectBuilder where({
    Condition? id,
    Condition? title,
    Condition? authorId,
    Condition? createdAt,
  }) {
    final newConditions = [...config.where];
    if (id != null) newConditions.add(id);
    if (title != null) newConditions.add(title);
    if (authorId != null) newConditions.add(authorId);
    if (createdAt != null) newConditions.add(createdAt);

    return ArticlesSelectBuilder(
      db,
      ArticlesSelectConfig(
        where: newConditions,
        limit: config.limit,
        offset: config.offset,
      ),
    );
  }

  ArticlesSelectBuilder limit(int limit) {
    return ArticlesSelectBuilder(
      db,
      ArticlesSelectConfig(
        where: config.where,
        limit: limit,
        offset: config.offset,
      ),
    );
  }

  ArticlesSelectBuilder offset(int offset) {
    return ArticlesSelectBuilder(
      db,
      ArticlesSelectConfig(
        where: config.where,
        limit: config.limit,
        offset: offset,
      ),
    );
  }
}

class ArticlesSelectConfig {
  final List<Condition> where;
  final int? limit;
  final int? offset;

  ArticlesSelectConfig({
    required List<Condition>? where,
    required this.limit,
    required this.offset,
  }) : where = where ?? [];

  @override
  String toString() {
    return 'ArticlesSelectConfig(where: $where, limit: $limit, offset: $offset)';
  }
}

class ArticlesInsertBuilder extends QueryFuture<int> with FutureMixin<int> {
  final PostgresQueryable db;
  final String? _id;
  final String? _title;
  final String? _authorId;
  final DateTime? _createdAt;

  ArticlesInsertBuilder(
    this.db, {
    String? id,
    String? title,
    String? authorId,
    DateTime? createdAt,
  }) : _id = id,
       _title = title,
       _authorId = authorId,
       _createdAt = createdAt;

  ArticlesInsertBuilder values({
    required String id,
    required String title,
    String? authorId,
    required DateTime createdAt,
  }) {
    return ArticlesInsertBuilder(
      db,
      id: id,
      title: title,
      authorId: authorId,
      createdAt: createdAt,
    );
  }

  @override
  Future<int> execute() {
    if (_id == null) {
      throw StateError('Field `id` is required but not set');
    }
    if (_title == null) {
      throw StateError('Field `title` is required but not set');
    }
    if (_createdAt == null) {
      throw StateError('Field `createdAt` is required but not set');
    }
    final sql =
        'INSERT INTO articles (id, title, author_id, created_at) VALUES (:id, :title, :author_id, :created_at)';
    final params = {
      'id': _id,
      'title': _title,
      'author_id': _authorId,
      'created_at': _createdAt,
    };
    return db.execute(sql, params: params);
  }
}

class ArticlesUpdateBuilder extends QueryFuture<int> with FutureMixin<int> {
  final PostgresQueryable db;
  final String? _id;
  final String? _title;
  final String? _authorId;
  final DateTime? _createdAt;
  final List<Condition> _where;

  ArticlesUpdateBuilder(
    this.db, {
    String? id,
    String? title,
    String? authorId,
    DateTime? createdAt,
    List<Condition>? where,
  }) : _id = id,
       _title = title,
       _authorId = authorId,
       _createdAt = createdAt,
       _where = where ?? [];

  // SET句（更新するカラムを指定）
  ArticlesUpdateBuilder set({
    String? id,
    String? title,
    String? authorId,
    DateTime? createdAt,
  }) {
    return ArticlesUpdateBuilder(
      db,
      where: _where,
      id: id,
      title: title,
      authorId: authorId,
      createdAt: createdAt,
    );
  }

  // WHERE句（SelectBuilderと同じ仕組み）
  ArticlesUpdateBuilder where({
    Condition? id,
    Condition? title,
    Condition? authorId,
    Condition? createdAt,
  }) {
    final newConditions = [..._where];
    if (id != null) newConditions.add(id);
    if (title != null) newConditions.add(title);
    if (authorId != null) newConditions.add(authorId);
    if (createdAt != null) newConditions.add(createdAt);
    return ArticlesUpdateBuilder(
      db,
      where: newConditions,
      id: _id,
      title: _title,
      authorId: _authorId,
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
    if (_title != null) {
      updates.add('title = :set_title');
      params['set_title'] = _title;
    }
    if (_authorId != null) {
      updates.add('author_id = :set_author_id');
      params['set_author_id'] = _authorId;
    }
    if (_createdAt != null) {
      updates.add('created_at = :set_created_at');
      params['set_created_at'] = _createdAt;
    }

    if (updates.isEmpty) throw StateError('No fields to update');

    final sqlBuffer = StringBuffer('UPDATE articles SET ${updates.join(', ')}');

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

class ArticlesDeleteBuilder extends QueryFuture<int> with FutureMixin<int> {
  final PostgresQueryable db;
  final List<Condition> _where;

  ArticlesDeleteBuilder(this.db, [List<Condition>? where])
    : _where = where ?? [];

  // WHERE句（SelectBuilderと同じ仕組み）
  ArticlesDeleteBuilder where({
    Condition? id,
    Condition? title,
    Condition? authorId,
    Condition? createdAt,
  }) {
    final newConditions = [..._where];
    if (id != null) newConditions.add(id);
    if (title != null) newConditions.add(title);
    if (authorId != null) newConditions.add(authorId);
    if (createdAt != null) newConditions.add(createdAt);
    return ArticlesDeleteBuilder(db, newConditions);
  }

  @override
  Future<int> execute() {
    final sqlBuffer = StringBuffer('DELETE FROM articles');
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

typedef ArticlesWithAuthorRow = ({ArticlesRow article, UsersRow? author});

class ArticlesWithAuthorSelectConfig {
  final List<Condition> where;
  final int? limit;
  final int? offset;

  ArticlesWithAuthorSelectConfig({
    required List<Condition>? where,
    required this.limit,
    required this.offset,
  }) : where = where ?? [];
}

class ArticlesWithAuthorSelectBuilder
    extends QueryFuture<List<ArticlesWithAuthorRow>>
    with FutureMixin<List<ArticlesWithAuthorRow>> {
  final PostgresQueryable db;
  final ArticlesWithAuthorSelectConfig config;

  ArticlesWithAuthorSelectBuilder(this.db, this.config);

  @override
  Future<List<ArticlesWithAuthorRow>> execute() {
    final sqlBuffer = StringBuffer(
      'SELECT articles.id AS articles_id, articles.title AS articles_title, articles.author_id AS articles_author_id, articles.created_at AS articles_created_at, users.id AS users_id, users.name AS users_name, users.age AS users_age, users.active AS users_active, users.created_at AS users_created_at FROM articles',
    );
    sqlBuffer.write(' LEFT JOIN users ON articles.author_id = users.id');
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
          article: (
            id: row['articles_id'] as String,
            title: row['articles_title'] as String,
            authorId: row['articles_author_id'] as String?,
            createdAt: row['articles_created_at'] as DateTime,
          ),
          author: row['users_id'] == null
              ? null
              : (
                  id: row['users_id'] as String,
                  name: row['users_name'] as String,
                  age: row['users_age'] as int?,
                  active: row['users_active'] as int,
                  createdAt: row['users_created_at'] as DateTime,
                ),
        );
      }).toList();
    });
  }

  ArticlesWithAuthorSelectBuilder where({
    Condition? id,
    Condition? title,
    Condition? authorId,
    Condition? createdAt,
  }) {
    final newConditions = [...config.where];
    if (id != null) newConditions.add(id);
    if (title != null) newConditions.add(title);
    if (authorId != null) newConditions.add(authorId);
    if (createdAt != null) newConditions.add(createdAt);
    return ArticlesWithAuthorSelectBuilder(
      db,
      ArticlesWithAuthorSelectConfig(
        where: newConditions,
        limit: config.limit,
        offset: config.offset,
      ),
    );
  }

  ArticlesWithAuthorSelectBuilder limit(int limit) {
    return ArticlesWithAuthorSelectBuilder(
      db,
      ArticlesWithAuthorSelectConfig(
        where: config.where,
        limit: limit,
        offset: config.offset,
      ),
    );
  }

  ArticlesWithAuthorSelectBuilder offset(int offset) {
    return ArticlesWithAuthorSelectBuilder(
      db,
      ArticlesWithAuthorSelectConfig(
        where: config.where,
        limit: config.limit,
        offset: offset,
      ),
    );
  }
}

extension PostgresCommentsDatabaseX on PostgresDatabase {
  CommentsQueryBuilder get comments => CommentsQueryBuilder(this);
}

extension PostgresCommentsTransactionX on PostgresTransaction {
  CommentsQueryBuilder get comments => CommentsQueryBuilder(this);
}

// Query Builder for table: comments
class CommentsQueryBuilder {
  final PostgresQueryable db;

  CommentsQueryBuilder(this.db);

  CommentsSelectBuilder select() {
    return CommentsSelectBuilder(
      db,
      CommentsSelectConfig(where: null, limit: null, offset: null),
    );
  }

  CommentsInsertBuilder insert() {
    return CommentsInsertBuilder(db);
  }

  CommentsUpdateBuilder update() {
    return CommentsUpdateBuilder(db);
  }

  CommentsDeleteBuilder delete() {
    return CommentsDeleteBuilder(db);
  }
}

typedef CommentsRow = ({
  String id,
  String content,
  String postId,
  String userId,
  DateTime createdAt,
});

class CommentsSelectBuilder extends QueryFuture<List<CommentsRow>>
    with FutureMixin<List<CommentsRow>> {
  final PostgresQueryable db;
  final CommentsSelectConfig config;

  CommentsSelectBuilder(this.db, this.config);

  @override
  Future<List<CommentsRow>> execute() {
    final sqlBuffer = StringBuffer('SELECT * FROM comments');
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
          content: row['content'] as String,
          postId: row['post_id'] as String,
          userId: row['user_id'] as String,
          createdAt: row['created_at'] as DateTime,
        );
      }).toList();
    });
  }

  CommentsWithPostSelectBuilder withPost() {
    return CommentsWithPostSelectBuilder(
      db,
      CommentsWithPostSelectConfig(
        where: config.where,
        limit: config.limit,
        offset: config.offset,
      ),
    );
  }

  CommentsWithUserSelectBuilder withUser() {
    return CommentsWithUserSelectBuilder(
      db,
      CommentsWithUserSelectConfig(
        where: config.where,
        limit: config.limit,
        offset: config.offset,
      ),
    );
  }

  CommentsSelectBuilder where({
    Condition? id,
    Condition? content,
    Condition? postId,
    Condition? userId,
    Condition? createdAt,
  }) {
    final newConditions = [...config.where];
    if (id != null) newConditions.add(id);
    if (content != null) newConditions.add(content);
    if (postId != null) newConditions.add(postId);
    if (userId != null) newConditions.add(userId);
    if (createdAt != null) newConditions.add(createdAt);

    return CommentsSelectBuilder(
      db,
      CommentsSelectConfig(
        where: newConditions,
        limit: config.limit,
        offset: config.offset,
      ),
    );
  }

  CommentsSelectBuilder limit(int limit) {
    return CommentsSelectBuilder(
      db,
      CommentsSelectConfig(
        where: config.where,
        limit: limit,
        offset: config.offset,
      ),
    );
  }

  CommentsSelectBuilder offset(int offset) {
    return CommentsSelectBuilder(
      db,
      CommentsSelectConfig(
        where: config.where,
        limit: config.limit,
        offset: offset,
      ),
    );
  }
}

class CommentsSelectConfig {
  final List<Condition> where;
  final int? limit;
  final int? offset;

  CommentsSelectConfig({
    required List<Condition>? where,
    required this.limit,
    required this.offset,
  }) : where = where ?? [];

  @override
  String toString() {
    return 'CommentsSelectConfig(where: $where, limit: $limit, offset: $offset)';
  }
}

class CommentsInsertBuilder extends QueryFuture<int> with FutureMixin<int> {
  final PostgresQueryable db;
  final String? _id;
  final String? _content;
  final String? _postId;
  final String? _userId;
  final DateTime? _createdAt;

  CommentsInsertBuilder(
    this.db, {
    String? id,
    String? content,
    String? postId,
    String? userId,
    DateTime? createdAt,
  }) : _id = id,
       _content = content,
       _postId = postId,
       _userId = userId,
       _createdAt = createdAt;

  CommentsInsertBuilder values({
    required String id,
    required String content,
    required String postId,
    required String userId,
    required DateTime createdAt,
  }) {
    return CommentsInsertBuilder(
      db,
      id: id,
      content: content,
      postId: postId,
      userId: userId,
      createdAt: createdAt,
    );
  }

  @override
  Future<int> execute() {
    if (_id == null) {
      throw StateError('Field `id` is required but not set');
    }
    if (_content == null) {
      throw StateError('Field `content` is required but not set');
    }
    if (_postId == null) {
      throw StateError('Field `postId` is required but not set');
    }
    if (_userId == null) {
      throw StateError('Field `userId` is required but not set');
    }
    if (_createdAt == null) {
      throw StateError('Field `createdAt` is required but not set');
    }
    final sql =
        'INSERT INTO comments (id, content, post_id, user_id, created_at) VALUES (:id, :content, :post_id, :user_id, :created_at)';
    final params = {
      'id': _id,
      'content': _content,
      'post_id': _postId,
      'user_id': _userId,
      'created_at': _createdAt,
    };
    return db.execute(sql, params: params);
  }
}

class CommentsUpdateBuilder extends QueryFuture<int> with FutureMixin<int> {
  final PostgresQueryable db;
  final String? _id;
  final String? _content;
  final String? _postId;
  final String? _userId;
  final DateTime? _createdAt;
  final List<Condition> _where;

  CommentsUpdateBuilder(
    this.db, {
    String? id,
    String? content,
    String? postId,
    String? userId,
    DateTime? createdAt,
    List<Condition>? where,
  }) : _id = id,
       _content = content,
       _postId = postId,
       _userId = userId,
       _createdAt = createdAt,
       _where = where ?? [];

  // SET句（更新するカラムを指定）
  CommentsUpdateBuilder set({
    String? id,
    String? content,
    String? postId,
    String? userId,
    DateTime? createdAt,
  }) {
    return CommentsUpdateBuilder(
      db,
      where: _where,
      id: id,
      content: content,
      postId: postId,
      userId: userId,
      createdAt: createdAt,
    );
  }

  // WHERE句（SelectBuilderと同じ仕組み）
  CommentsUpdateBuilder where({
    Condition? id,
    Condition? content,
    Condition? postId,
    Condition? userId,
    Condition? createdAt,
  }) {
    final newConditions = [..._where];
    if (id != null) newConditions.add(id);
    if (content != null) newConditions.add(content);
    if (postId != null) newConditions.add(postId);
    if (userId != null) newConditions.add(userId);
    if (createdAt != null) newConditions.add(createdAt);
    return CommentsUpdateBuilder(
      db,
      where: newConditions,
      id: _id,
      content: _content,
      postId: _postId,
      userId: _userId,
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
    if (_content != null) {
      updates.add('content = :set_content');
      params['set_content'] = _content;
    }
    if (_postId != null) {
      updates.add('post_id = :set_post_id');
      params['set_post_id'] = _postId;
    }
    if (_userId != null) {
      updates.add('user_id = :set_user_id');
      params['set_user_id'] = _userId;
    }
    if (_createdAt != null) {
      updates.add('created_at = :set_created_at');
      params['set_created_at'] = _createdAt;
    }

    if (updates.isEmpty) throw StateError('No fields to update');

    final sqlBuffer = StringBuffer('UPDATE comments SET ${updates.join(', ')}');

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

class CommentsDeleteBuilder extends QueryFuture<int> with FutureMixin<int> {
  final PostgresQueryable db;
  final List<Condition> _where;

  CommentsDeleteBuilder(this.db, [List<Condition>? where])
    : _where = where ?? [];

  // WHERE句（SelectBuilderと同じ仕組み）
  CommentsDeleteBuilder where({
    Condition? id,
    Condition? content,
    Condition? postId,
    Condition? userId,
    Condition? createdAt,
  }) {
    final newConditions = [..._where];
    if (id != null) newConditions.add(id);
    if (content != null) newConditions.add(content);
    if (postId != null) newConditions.add(postId);
    if (userId != null) newConditions.add(userId);
    if (createdAt != null) newConditions.add(createdAt);
    return CommentsDeleteBuilder(db, newConditions);
  }

  @override
  Future<int> execute() {
    final sqlBuffer = StringBuffer('DELETE FROM comments');
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

typedef CommentsWithPostRow = ({CommentsRow comment, PostsRow post});

class CommentsWithPostSelectConfig {
  final List<Condition> where;
  final int? limit;
  final int? offset;

  CommentsWithPostSelectConfig({
    required List<Condition>? where,
    required this.limit,
    required this.offset,
  }) : where = where ?? [];
}

class CommentsWithPostSelectBuilder
    extends QueryFuture<List<CommentsWithPostRow>>
    with FutureMixin<List<CommentsWithPostRow>> {
  final PostgresQueryable db;
  final CommentsWithPostSelectConfig config;

  CommentsWithPostSelectBuilder(this.db, this.config);

  @override
  Future<List<CommentsWithPostRow>> execute() {
    final sqlBuffer = StringBuffer(
      'SELECT comments.id AS comments_id, comments.content AS comments_content, comments.post_id AS comments_post_id, comments.user_id AS comments_user_id, comments.created_at AS comments_created_at, posts.id AS posts_id, posts.title AS posts_title, posts.content AS posts_content, posts.user_id AS posts_user_id, posts.created_at AS posts_created_at FROM comments',
    );
    sqlBuffer.write(' INNER JOIN posts ON comments.post_id = posts.id');
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
          comment: (
            id: row['comments_id'] as String,
            content: row['comments_content'] as String,
            postId: row['comments_post_id'] as String,
            userId: row['comments_user_id'] as String,
            createdAt: row['comments_created_at'] as DateTime,
          ),
          post: (
            id: row['posts_id'] as String,
            title: row['posts_title'] as String,
            content: row['posts_content'] as String,
            userId: row['posts_user_id'] as String,
            createdAt: row['posts_created_at'] as DateTime,
          ),
        );
      }).toList();
    });
  }

  CommentsWithPostWithUserSelectBuilder withUser() {
    return CommentsWithPostWithUserSelectBuilder(
      db,
      CommentsWithPostWithUserSelectConfig(
        where: config.where,
        limit: config.limit,
        offset: config.offset,
      ),
    );
  }

  CommentsWithPostSelectBuilder where({
    Condition? id,
    Condition? content,
    Condition? postId,
    Condition? userId,
    Condition? createdAt,
  }) {
    final newConditions = [...config.where];
    if (id != null) newConditions.add(id);
    if (content != null) newConditions.add(content);
    if (postId != null) newConditions.add(postId);
    if (userId != null) newConditions.add(userId);
    if (createdAt != null) newConditions.add(createdAt);
    return CommentsWithPostSelectBuilder(
      db,
      CommentsWithPostSelectConfig(
        where: newConditions,
        limit: config.limit,
        offset: config.offset,
      ),
    );
  }

  CommentsWithPostSelectBuilder limit(int limit) {
    return CommentsWithPostSelectBuilder(
      db,
      CommentsWithPostSelectConfig(
        where: config.where,
        limit: limit,
        offset: config.offset,
      ),
    );
  }

  CommentsWithPostSelectBuilder offset(int offset) {
    return CommentsWithPostSelectBuilder(
      db,
      CommentsWithPostSelectConfig(
        where: config.where,
        limit: config.limit,
        offset: offset,
      ),
    );
  }
}

typedef CommentsWithUserRow = ({CommentsRow comment, UsersRow user});

class CommentsWithUserSelectConfig {
  final List<Condition> where;
  final int? limit;
  final int? offset;

  CommentsWithUserSelectConfig({
    required List<Condition>? where,
    required this.limit,
    required this.offset,
  }) : where = where ?? [];
}

class CommentsWithUserSelectBuilder
    extends QueryFuture<List<CommentsWithUserRow>>
    with FutureMixin<List<CommentsWithUserRow>> {
  final PostgresQueryable db;
  final CommentsWithUserSelectConfig config;

  CommentsWithUserSelectBuilder(this.db, this.config);

  @override
  Future<List<CommentsWithUserRow>> execute() {
    final sqlBuffer = StringBuffer(
      'SELECT comments.id AS comments_id, comments.content AS comments_content, comments.post_id AS comments_post_id, comments.user_id AS comments_user_id, comments.created_at AS comments_created_at, users.id AS users_id, users.name AS users_name, users.age AS users_age, users.active AS users_active, users.created_at AS users_created_at FROM comments',
    );
    sqlBuffer.write(' INNER JOIN users ON comments.user_id = users.id');
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
          comment: (
            id: row['comments_id'] as String,
            content: row['comments_content'] as String,
            postId: row['comments_post_id'] as String,
            userId: row['comments_user_id'] as String,
            createdAt: row['comments_created_at'] as DateTime,
          ),
          user: (
            id: row['users_id'] as String,
            name: row['users_name'] as String,
            age: row['users_age'] as int?,
            active: row['users_active'] as int,
            createdAt: row['users_created_at'] as DateTime,
          ),
        );
      }).toList();
    });
  }

  CommentsWithPostWithUserSelectBuilder withPost() {
    return CommentsWithPostWithUserSelectBuilder(
      db,
      CommentsWithPostWithUserSelectConfig(
        where: config.where,
        limit: config.limit,
        offset: config.offset,
      ),
    );
  }

  CommentsWithUserSelectBuilder where({
    Condition? id,
    Condition? content,
    Condition? postId,
    Condition? userId,
    Condition? createdAt,
  }) {
    final newConditions = [...config.where];
    if (id != null) newConditions.add(id);
    if (content != null) newConditions.add(content);
    if (postId != null) newConditions.add(postId);
    if (userId != null) newConditions.add(userId);
    if (createdAt != null) newConditions.add(createdAt);
    return CommentsWithUserSelectBuilder(
      db,
      CommentsWithUserSelectConfig(
        where: newConditions,
        limit: config.limit,
        offset: config.offset,
      ),
    );
  }

  CommentsWithUserSelectBuilder limit(int limit) {
    return CommentsWithUserSelectBuilder(
      db,
      CommentsWithUserSelectConfig(
        where: config.where,
        limit: limit,
        offset: config.offset,
      ),
    );
  }

  CommentsWithUserSelectBuilder offset(int offset) {
    return CommentsWithUserSelectBuilder(
      db,
      CommentsWithUserSelectConfig(
        where: config.where,
        limit: config.limit,
        offset: offset,
      ),
    );
  }
}

typedef CommentsWithPostWithUserRow = ({
  CommentsRow comment,
  PostsRow post,
  UsersRow user,
});

class CommentsWithPostWithUserSelectConfig {
  final List<Condition> where;
  final int? limit;
  final int? offset;

  CommentsWithPostWithUserSelectConfig({
    required List<Condition>? where,
    required this.limit,
    required this.offset,
  }) : where = where ?? [];
}

class CommentsWithPostWithUserSelectBuilder
    extends QueryFuture<List<CommentsWithPostWithUserRow>>
    with FutureMixin<List<CommentsWithPostWithUserRow>> {
  final PostgresQueryable db;
  final CommentsWithPostWithUserSelectConfig config;

  CommentsWithPostWithUserSelectBuilder(this.db, this.config);

  @override
  Future<List<CommentsWithPostWithUserRow>> execute() {
    final sqlBuffer = StringBuffer(
      'SELECT comments.id AS comments_id, comments.content AS comments_content, comments.post_id AS comments_post_id, comments.user_id AS comments_user_id, comments.created_at AS comments_created_at, posts.id AS posts_id, posts.title AS posts_title, posts.content AS posts_content, posts.user_id AS posts_user_id, posts.created_at AS posts_created_at, users.id AS users_id, users.name AS users_name, users.age AS users_age, users.active AS users_active, users.created_at AS users_created_at FROM comments',
    );
    sqlBuffer.write(' INNER JOIN posts ON comments.post_id = posts.id');
    sqlBuffer.write(' INNER JOIN users ON comments.user_id = users.id');
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
          comment: (
            id: row['comments_id'] as String,
            content: row['comments_content'] as String,
            postId: row['comments_post_id'] as String,
            userId: row['comments_user_id'] as String,
            createdAt: row['comments_created_at'] as DateTime,
          ),
          post: (
            id: row['posts_id'] as String,
            title: row['posts_title'] as String,
            content: row['posts_content'] as String,
            userId: row['posts_user_id'] as String,
            createdAt: row['posts_created_at'] as DateTime,
          ),
          user: (
            id: row['users_id'] as String,
            name: row['users_name'] as String,
            age: row['users_age'] as int?,
            active: row['users_active'] as int,
            createdAt: row['users_created_at'] as DateTime,
          ),
        );
      }).toList();
    });
  }

  CommentsWithPostWithUserSelectBuilder where({
    Condition? id,
    Condition? content,
    Condition? postId,
    Condition? userId,
    Condition? createdAt,
  }) {
    final newConditions = [...config.where];
    if (id != null) newConditions.add(id);
    if (content != null) newConditions.add(content);
    if (postId != null) newConditions.add(postId);
    if (userId != null) newConditions.add(userId);
    if (createdAt != null) newConditions.add(createdAt);
    return CommentsWithPostWithUserSelectBuilder(
      db,
      CommentsWithPostWithUserSelectConfig(
        where: newConditions,
        limit: config.limit,
        offset: config.offset,
      ),
    );
  }

  CommentsWithPostWithUserSelectBuilder limit(int limit) {
    return CommentsWithPostWithUserSelectBuilder(
      db,
      CommentsWithPostWithUserSelectConfig(
        where: config.where,
        limit: limit,
        offset: config.offset,
      ),
    );
  }

  CommentsWithPostWithUserSelectBuilder offset(int offset) {
    return CommentsWithPostWithUserSelectBuilder(
      db,
      CommentsWithPostWithUserSelectConfig(
        where: config.where,
        limit: config.limit,
        offset: offset,
      ),
    );
  }
}
