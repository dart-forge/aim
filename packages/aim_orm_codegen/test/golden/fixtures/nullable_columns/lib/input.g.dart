// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'input.dart';

// **************************************************************************
// RecordPgTableGenerator
// **************************************************************************

extension PostgresProductsDatabaseX on PostgresDatabase {
  ProductsQueryBuilder get products => ProductsQueryBuilder(this);
}

extension PostgresProductsTransactionX on PostgresTransaction {
  ProductsQueryBuilder get products => ProductsQueryBuilder(this);
}

// Query Builder for table: products
class ProductsQueryBuilder {
  final PostgresQueryable db;

  ProductsQueryBuilder(this.db);

  ProductsSelectBuilder select() {
    return ProductsSelectBuilder(
      db,
      ProductsSelectConfig(where: null, limit: null, offset: null),
    );
  }

  ProductsInsertBuilder insert() {
    return ProductsInsertBuilder(db);
  }

  ProductsUpdateBuilder update() {
    return ProductsUpdateBuilder(db);
  }

  ProductsDeleteBuilder delete() {
    return ProductsDeleteBuilder(db);
  }
}

typedef ProductsRow = ({int id, String name, String? description, int? price});

class ProductsSelectBuilder extends QueryFuture<List<ProductsRow>>
    with FutureMixin<List<ProductsRow>> {
  final PostgresQueryable db;
  final ProductsSelectConfig config;

  ProductsSelectBuilder(this.db, this.config);

  @override
  Future<List<ProductsRow>> execute() {
    final sqlBuffer = StringBuffer('SELECT * FROM products');
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
          id: row['id'] as int,
          name: row['name'] as String,
          description: row['description'] as String?,
          price: row['price'] as int?,
        );
      }).toList();
    });
  }

  ProductsSelectBuilder where({
    Condition? id,
    Condition? name,
    Condition? description,
    Condition? price,
  }) {
    final newConditions = [...config.where];
    if (id != null) newConditions.add(id);
    if (name != null) newConditions.add(name);
    if (description != null) newConditions.add(description);
    if (price != null) newConditions.add(price);

    return ProductsSelectBuilder(
      db,
      ProductsSelectConfig(
        where: newConditions,
        limit: config.limit,
        offset: config.offset,
      ),
    );
  }

  ProductsSelectBuilder limit(int limit) {
    return ProductsSelectBuilder(
      db,
      ProductsSelectConfig(
        where: config.where,
        limit: limit,
        offset: config.offset,
      ),
    );
  }

  ProductsSelectBuilder offset(int offset) {
    return ProductsSelectBuilder(
      db,
      ProductsSelectConfig(
        where: config.where,
        limit: config.limit,
        offset: offset,
      ),
    );
  }
}

class ProductsSelectConfig {
  final List<Condition> where;
  final int? limit;
  final int? offset;

  ProductsSelectConfig({
    required List<Condition>? where,
    required this.limit,
    required this.offset,
  }) : where = where ?? [];

  @override
  String toString() {
    return 'ProductsSelectConfig(where: $where, limit: $limit, offset: $offset)';
  }
}

class ProductsInsertBuilder extends QueryFuture<int> with FutureMixin<int> {
  final PostgresQueryable db;
  final int? _id;
  final String? _name;
  final String? _description;
  final int? _price;

  ProductsInsertBuilder(
    this.db, {
    int? id,
    String? name,
    String? description,
    int? price,
  }) : _id = id,
       _name = name,
       _description = description,
       _price = price;

  ProductsInsertBuilder values({
    required int id,
    required String name,
    String? description,
    int? price,
  }) {
    return ProductsInsertBuilder(
      db,
      id: id,
      name: name,
      description: description,
      price: price,
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
    final sql =
        'INSERT INTO products (id, name, description, price) VALUES (:id, :name, :description, :price)';
    final params = {
      'id': _id,
      'name': _name,
      'description': _description,
      'price': _price,
    };
    return db.execute(sql, params: params);
  }
}

class ProductsUpdateBuilder extends QueryFuture<int> with FutureMixin<int> {
  final PostgresQueryable db;
  final int? _id;
  final String? _name;
  final String? _description;
  final int? _price;
  final List<Condition> _where;

  ProductsUpdateBuilder(
    this.db, {
    int? id,
    String? name,
    String? description,
    int? price,
    List<Condition>? where,
  }) : _id = id,
       _name = name,
       _description = description,
       _price = price,
       _where = where ?? [];

  // SET句（更新するカラムを指定）
  ProductsUpdateBuilder set({
    int? id,
    String? name,
    String? description,
    int? price,
  }) {
    return ProductsUpdateBuilder(
      db,
      where: _where,
      id: id,
      name: name,
      description: description,
      price: price,
    );
  }

  // WHERE句（SelectBuilderと同じ仕組み）
  ProductsUpdateBuilder where({
    Condition? id,
    Condition? name,
    Condition? description,
    Condition? price,
  }) {
    final newConditions = [..._where];
    if (id != null) newConditions.add(id);
    if (name != null) newConditions.add(name);
    if (description != null) newConditions.add(description);
    if (price != null) newConditions.add(price);
    return ProductsUpdateBuilder(
      db,
      where: newConditions,
      id: _id,
      name: _name,
      description: _description,
      price: _price,
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
    if (_description != null) {
      updates.add('description = :set_description');
      params['set_description'] = _description;
    }
    if (_price != null) {
      updates.add('price = :set_price');
      params['set_price'] = _price;
    }

    if (updates.isEmpty) throw StateError('No fields to update');

    final sqlBuffer = StringBuffer('UPDATE products SET ${updates.join(', ')}');

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

class ProductsDeleteBuilder extends QueryFuture<int> with FutureMixin<int> {
  final PostgresQueryable db;
  final List<Condition> _where;

  ProductsDeleteBuilder(this.db, [List<Condition>? where])
    : _where = where ?? [];

  // WHERE句（SelectBuilderと同じ仕組み）
  ProductsDeleteBuilder where({
    Condition? id,
    Condition? name,
    Condition? description,
    Condition? price,
  }) {
    final newConditions = [..._where];
    if (id != null) newConditions.add(id);
    if (name != null) newConditions.add(name);
    if (description != null) newConditions.add(description);
    if (price != null) newConditions.add(price);
    return ProductsDeleteBuilder(db, newConditions);
  }

  @override
  Future<int> execute() {
    final sqlBuffer = StringBuffer('DELETE FROM products');
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
