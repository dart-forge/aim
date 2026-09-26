import 'dart:convert';

import 'package:aim_orm_postgres/aim_orm_postgres.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:glob/glob.dart';
import 'package:source_gen/source_gen.dart';

class RecordPgTableGenerator extends GeneratorForAnnotation<PgTable> {
  @override
  Future<String> generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) async {
    final tableName = annotation.peek('name')?.stringValue;

    if (tableName == null || tableName.isEmpty) {
      throw InvalidGenerationSourceError(
        'The `name` parameter in `@PgTable` annotation cannot be null or empty.',
        element: element,
      );
    }

    if (element is! TopLevelVariableElement) {
      throw InvalidGenerationSourceError(
        '`@PgTable` can only be applied to top-level variables.',
        element: element,
      );
    }

    final type = element.type;
    if (type is! RecordType) {
      throw InvalidGenerationSourceError(
        'The variable `${element.name}` must be of a record type to use the `@Table` annotation.',
        element: element,
      );
    }

    if (element.name == null || element.name!.isEmpty) {
      throw InvalidGenerationSourceError(
        'The variable name cannot be null or empty.',
        element: element,
      );
    }

    final libraryReader = await buildStep.resolver.compilationUnitFor(
      buildStep.inputId,
    );
    final recordVisitor = RecordVisitor(element.name!);
    libraryReader.accept(recordVisitor);
    final recordLiteral = recordVisitor.foundRecord;

    // Phase 1で収集された全テーブル情報をJSONから読み込み
    final allTables = await _readAllTableInfo(buildStep);

    final fields = <({String name, Expression expression})>[];
    if (recordLiteral != null) {
      for (final field in recordLiteral.fields) {
        if (field is RecordLiteralNamedField) {
          final fieldName = field.name.lexeme;
          final expression = field.fieldExpression;
          fields.add((name: fieldName, expression: expression));
        }
      }
    }

    final records = fields.map((field) {
      final record = analyzeField(field.name, field.expression);
      return record;
    }).toList();

    final buffer = StringBuffer();
    generateExtensionForTable(buffer, tableName);
    generateTransactionExtensionForTable(buffer, tableName);
    generateQueryBuilder(buffer, tableName);
    generateSelectRowBuilder(buffer, tableName, records);
    generateSelectBuilder(buffer, tableName, records, allTables);
    generateSelectConfig(buffer, tableName);
    generateInsertBuilder(buffer, tableName, records);
    generateUpdateBuilder(buffer, tableName, records);
    generateDeleteBuilder(buffer, tableName, records);
    generateRelationSelectBuilder(buffer, tableName, records, allTables);

    return buffer.toString();
  }

  void generateExtensionForTable(StringBuffer buffer, String tableName) {
    final className = '${capitalize(tableName)}QueryBuilder';
    buffer.writeln(
      'extension Postgres${capitalize(tableName)}DatabaseX on PostgresDatabase {',
    );
    buffer.writeln('  $className get $tableName => $className(this);');
    buffer.writeln('}');
    buffer.writeln();
  }

  void generateTransactionExtensionForTable(
    StringBuffer buffer,
    String tableName,
  ) {
    final className = '${capitalize(tableName)}QueryBuilder';
    buffer.writeln(
      'extension Postgres${capitalize(tableName)}TransactionX on PostgresTransaction {',
    );
    buffer.writeln('  $className get $tableName => $className(this);');
    buffer.writeln('}');
    buffer.writeln();
  }

  void generateQueryBuilder(StringBuffer buffer, String tableName) {
    buffer.writeln('// Query Builder for table: $tableName');
    buffer.writeln('class ${capitalize(tableName)}QueryBuilder {');
    buffer.writeln('  final PostgresQueryable db;');
    buffer.writeln();
    buffer.writeln('  ${capitalize(tableName)}QueryBuilder(this.db);');
    buffer.writeln();
    buffer.writeln('${capitalize(tableName)}SelectBuilder select() {');
    buffer.writeln('  return ${capitalize(tableName)}SelectBuilder(');
    buffer.writeln('    db,');
    buffer.writeln(
      '    ${capitalize(tableName)}SelectConfig(where: null, limit: null, offset: null),',
    );
    buffer.writeln('  );');
    buffer.writeln('}');
    buffer.writeln();
    buffer.writeln('${capitalize(tableName)}InsertBuilder insert() {');
    buffer.writeln('  return ${capitalize(tableName)}InsertBuilder(db);');
    buffer.writeln('}');
    buffer.writeln();
    buffer.writeln('${capitalize(tableName)}UpdateBuilder update() {');
    buffer.writeln('  return ${capitalize(tableName)}UpdateBuilder(db);');
    buffer.writeln('}');
    buffer.writeln();
    buffer.writeln('${capitalize(tableName)}DeleteBuilder delete() {');
    buffer.writeln('  return ${capitalize(tableName)}DeleteBuilder(db);');
    buffer.writeln('}');
    buffer.writeln('}');
    buffer.writeln();
  }

  void generateSelectRowBuilder(
    StringBuffer buffer,
    String tableName,
    List<AnalyzedField> fields,
  ) {
    buffer.writeln('typedef ${capitalize(tableName)}Row = ({');
    buffer.writeln(
      fields
          .map(
            (f) => '${f.returnType}${f.isNullable ? '?' : ''} ${f.fieldName}',
          )
          .join(','),
    );
    buffer.writeln('});');
    buffer.writeln();
  }

  void generateSelectBuilder(
    StringBuffer buffer,
    String tableName,
    List<AnalyzedField> fields,
    Map<String, List<AnalyzedField>> allTables,
  ) {
    final tableCapitalized = capitalize(tableName);

    buffer.writeln(
      'class ${tableCapitalized}SelectBuilder extends QueryFuture<List<${tableCapitalized}Row>> with FutureMixin<List<${tableCapitalized}Row>> {',
    );
    buffer.writeln('  final PostgresQueryable db;');
    buffer.writeln('  final ${tableCapitalized}SelectConfig config;');
    buffer.writeln();
    buffer.writeln(
      '  ${tableCapitalized}SelectBuilder(this.db, this.config);',
    );
    buffer.writeln();
    buffer.writeln('  @override');
    buffer.writeln('  Future<List<${tableCapitalized}Row>> execute() {');
    buffer.writeln(
      '    final sqlBuffer = StringBuffer(\'SELECT * FROM $tableName\');',
    );
    buffer.writeln('    final params = <String, dynamic>{};');
    buffer.writeln();
    buffer.writeln('    if (config.where.isNotEmpty) {');
    buffer.writeln('      sqlBuffer.write(\' WHERE \');');
    buffer.writeln('      final whereClauses = <String>[];');
    buffer.writeln();
    buffer.writeln('      for (var i = 0; i < config.where.length; i++) {');
    buffer.writeln('        final condition = config.where[i];');
    buffer.writeln('        whereClauses.add(condition.toSql(i));');
    buffer.writeln('        params.addAll(condition.toParams(i));');
    buffer.writeln('      }');
    buffer.writeln();
    buffer.writeln('      sqlBuffer.write(whereClauses.join(\' AND \'));');
    buffer.writeln('    }');
    buffer.writeln();
    buffer.writeln('    if (config.limit != null) {');
    buffer.writeln('      sqlBuffer.write(\' LIMIT \${config.limit}\');');
    buffer.writeln('    }');
    buffer.writeln();
    buffer.writeln('    if (config.offset != null) {');
    buffer.writeln('      sqlBuffer.write(\' OFFSET \${config.offset}\');');
    buffer.writeln('    }');
    buffer.writeln();
    buffer.writeln('    final sql = sqlBuffer.toString();');
    buffer.writeln('    return db.query(sql, params: params).then((result) {');
    buffer.writeln('      return result.map((row) {');
    buffer.writeln('        return (');
    for (final field in fields) {
      switch (field.columnMapper) {
        case PgColumnMapper.integer:
        case PgColumnMapper.serial:
          buffer.writeln(
            '  ${field.fieldName}: row[\'${field.columnName}\'] as int${field.isNullable ? '?' : ''},',
          );
          break;
        case PgColumnMapper.varchar:
        case PgColumnMapper.text:
        case PgColumnMapper.uuid:
          buffer.writeln(
            '  ${field.fieldName}: row[\'${field.columnName}\'] as String${field.isNullable ? '?' : ''},',
          );
          break;
        case PgColumnMapper.timestamp:
          buffer.writeln(
            '  ${field.fieldName}: row[\'${field.columnName}\'] as DateTime${field.isNullable ? '?' : ''},',
          );
          break;
        case PgColumnMapper.jsonb:
          buffer.writeln(
            '  ${field.fieldName}: row[\'${field.columnName}\'] as Map<String, dynamic>${field.isNullable ? '?' : ''},',
          );
          break;
        case PgColumnMapper.unknown:
          buffer.writeln('  ${field.fieldName}: row[\'${field.columnName}\'],');
      }
    }
    buffer.writeln('        );');
    buffer.writeln('      }).toList();');
    buffer.writeln('    });');
    buffer.writeln('  }');
    buffer.writeln();

    // FK フィールドに対する withXxx() メソッドを生成
    final fkFields = fields.where((f) => f.refTable != null && f.refColumn != null).toList();
    for (final fk in fkFields) {
      final relationName = _inferRelationName(fk.fieldName, fk.refTable!);
      final withBuilderName = '${tableCapitalized}With${capitalize(relationName)}SelectBuilder';
      final withConfigName = '${tableCapitalized}With${capitalize(relationName)}SelectConfig';

      buffer.writeln('  $withBuilderName with${capitalize(relationName)}() {');
      buffer.writeln('    return $withBuilderName(');
      buffer.writeln('      db,');
      buffer.writeln('      $withConfigName(');
      buffer.writeln('        where: config.where,');
      buffer.writeln('        limit: config.limit,');
      buffer.writeln('        offset: config.offset,');
      buffer.writeln('      ),');
      buffer.writeln('    );');
      buffer.writeln('  }');
      buffer.writeln();
    }

    buffer.writeln('  ${tableCapitalized}SelectBuilder where({');
    for (final field in fields) {
      buffer.writeln('    Condition? ${field.fieldName},');
    }
    buffer.writeln('  }) {');
    buffer.writeln('    final newConditions = [...config.where];');
    for (final field in fields) {
      buffer.writeln('    if (${field.fieldName} != null) ');
      buffer.writeln('      newConditions.add(${field.fieldName});');
    }
    buffer.writeln();
    buffer.writeln('    return ${tableCapitalized}SelectBuilder(');
    buffer.writeln('      db,');
    buffer.writeln('      ${tableCapitalized}SelectConfig(');
    buffer.writeln('        where: newConditions,');
    buffer.writeln('        limit: config.limit,');
    buffer.writeln('        offset: config.offset,');
    buffer.writeln('      ),');
    buffer.writeln('    );');
    buffer.writeln('  }');
    buffer.writeln();

    buffer.writeln(
      '  ${tableCapitalized}SelectBuilder limit(int limit) {',
    );
    buffer.writeln('    return ${tableCapitalized}SelectBuilder(');
    buffer.writeln('      db,');
    buffer.writeln('      ${tableCapitalized}SelectConfig(');
    buffer.writeln('        where: config.where,');
    buffer.writeln('        limit: limit,');
    buffer.writeln('        offset: config.offset,');
    buffer.writeln('      ),');
    buffer.writeln('    );');
    buffer.writeln('  }');
    buffer.writeln();

    buffer.writeln(
      '  ${tableCapitalized}SelectBuilder offset(int offset) {',
    );
    buffer.writeln('    return ${tableCapitalized}SelectBuilder(');
    buffer.writeln('      db,');
    buffer.writeln('      ${tableCapitalized}SelectConfig(');
    buffer.writeln('        where: config.where,');
    buffer.writeln('        limit: config.limit,');
    buffer.writeln('        offset: offset,');
    buffer.writeln('      ),');
    buffer.writeln('    );');
    buffer.writeln('  }');
    buffer.writeln('}');
    buffer.writeln();
  }

  void generateSelectConfig(StringBuffer buffer, String tableName) {
    buffer.writeln('class ${capitalize(tableName)}SelectConfig {');
    buffer.writeln('  final List<Condition> where;');
    buffer.writeln('  final int? limit;');
    buffer.writeln('  final int? offset;');
    buffer.writeln();
    buffer.writeln('  ${capitalize(tableName)}SelectConfig({');
    buffer.writeln('    required List<Condition>? where,');
    buffer.writeln('    required this.limit,');
    buffer.writeln('    required this.offset,');
    buffer.writeln('  }) : where = where ?? [];');
    buffer.writeln();
    buffer.writeln('  @override');
    buffer.writeln('  String toString() {');
    buffer.writeln(
      "    return '${capitalize(tableName)}SelectConfig(where: \$where, limit: \$limit, offset: \$offset)';",
    );
    buffer.writeln('  }');
    buffer.writeln('}');
    buffer.writeln();
  }

  /// Whether the database fills [field] when an insert leaves it out: a
  /// serial column takes the next value of its sequence, a column with a
  /// default takes that default.
  ///
  /// Only a NOT NULL column qualifies. For a nullable parameter, null cannot
  /// mean both "not given" and "NULL wanted", and today's generated code
  /// sends an explicit NULL for an unset nullable column — changing that
  /// would hand a default to callers who asked for NULL.
  bool _databaseFills(AnalyzedField field) =>
      !field.isNullable &&
      (field.columnMapper == PgColumnMapper.serial || field.hasDefault);

  void generateInsertBuilder(
    StringBuffer buffer,
    String tableName,
    List<AnalyzedField> fields,
  ) {
    buffer.writeln(
      'class ${capitalize(tableName)}InsertBuilder extends QueryFuture<int> with FutureMixin<int> {',
    );
    buffer.writeln('  final PostgresQueryable db;');
    for (final field in fields) {
      buffer.writeln('  final ${field.returnType}? _${field.fieldName};');
    }
    buffer.writeln();
    buffer.writeln('  ${capitalize(tableName)}InsertBuilder(this.db, {');
    for (final field in fields) {
      buffer.writeln('    ${field.returnType}? ${field.fieldName},');
    }
    buffer.writeln(
      '  }): ${fields.map((f) => '_${f.fieldName} = ${f.fieldName}').join(', ')};',
    );
    buffer.writeln();
    buffer.writeln('  ${capitalize(tableName)}InsertBuilder values({');
    for (final field in fields) {
      final optional = field.isNullable || _databaseFills(field);
      buffer.writeln(
        '    ${optional ? '' : 'required'} ${field.returnType}${optional ? '?' : ''} ${field.fieldName},',
      );
    }
    buffer.writeln('  }) {');
    buffer.writeln('    return ${capitalize(tableName)}InsertBuilder(db,');
    for (final field in fields) {
      buffer.writeln('      ${field.fieldName}: ${field.fieldName},');
    }
    buffer.writeln('    );');
    buffer.writeln('  }');
    buffer.writeln();
    buffer.writeln('  @override');
    buffer.writeln('  Future<int> execute() {');
    for (final field in fields) {
      if (!field.isNullable && !_databaseFills(field)) {
        buffer.writeln('    if (_${field.fieldName} == null) {');
        buffer.writeln(
          "      throw StateError('Field `${field.fieldName}` is required but not set');",
        );
        buffer.writeln('    }');
      }
    }

    final filled = fields.where(_databaseFills).toList();
    if (filled.isNotEmpty) {
      buffer.writeln(
        '    // A column left unset here is filled by the database: a serial takes',
      );
      buffer.writeln(
        '    // the next value of its sequence, a column with a default takes that.',
      );
      for (final field in filled) {
        buffer.writeln(
          "    final ${field.fieldName}Value = _${field.fieldName} == null ? 'DEFAULT' : ':${field.columnName}';",
        );
      }
    }

    final columnNames = fields.map((r) => r.columnName).toList();
    final valuePlaceholders = fields.map((field) {
      if (_databaseFills(field)) return '\$${field.fieldName}Value';
      return ':${field.columnName}';
    }).toList();
    buffer.writeln(
      "    final sql = 'INSERT INTO $tableName (${columnNames.join(', ')}) "
      "VALUES (${valuePlaceholders.join(', ')})';",
    );
    buffer.writeln('    final params = {');
    for (final field in fields) {
      if (_databaseFills(field)) {
        buffer.writeln(
          "      if (_${field.fieldName} != null) '${field.columnName}': _${field.fieldName},",
        );
      } else {
        buffer.writeln("      '${field.columnName}': _${field.fieldName},");
      }
    }
    buffer.writeln('    };');
    buffer.writeln('    return db.execute(sql, params: params);');
    buffer.writeln('  }');
    buffer.writeln('}');
    buffer.writeln();
  }

  void generateUpdateBuilder(
    StringBuffer buffer,
    String tableName,
    List<AnalyzedField> fields,
  ) {
    buffer.writeln(
      'class ${capitalize(tableName)}UpdateBuilder extends QueryFuture<int> with FutureMixin<int> {',
    );
    buffer.writeln('  final PostgresQueryable db;');
    for (final field in fields) {
      buffer.writeln('  final ${field.returnType}? _${field.fieldName};');
    }
    buffer.writeln('  final List<Condition> _where;');
    buffer.writeln();
    buffer.writeln(
      '  ${capitalize(tableName)}UpdateBuilder(this.db, {${fields.map((r) => '${r.returnType}? ${r.fieldName}').join(', ')}, List<Condition>? where})',
    );
    buffer.writeln(
      '    : ${fields.map((f) => '_${f.fieldName} = ${f.fieldName}').join(', ')}, _where = where ?? [];',
    );
    buffer.writeln();
    buffer.writeln('  // SET句（更新するカラムを指定）');
    buffer.writeln('  ${capitalize(tableName)}UpdateBuilder set({');
    for (final record in fields) {
      buffer.writeln('    ${record.returnType}? ${record.fieldName},');
    }
    buffer.writeln('  }) {');
    buffer.writeln(
      '    return ${capitalize(tableName)}UpdateBuilder(db, where: _where,',
    );
    for (final record in fields) {
      buffer.writeln('      ${record.fieldName}: ${record.fieldName},');
    }
    buffer.writeln(');');
    buffer.writeln('  }');
    buffer.writeln();
    buffer.writeln('  // WHERE句（SelectBuilderと同じ仕組み）');
    buffer.writeln('  ${capitalize(tableName)}UpdateBuilder where({');
    for (final record in fields) {
      buffer.writeln('    Condition? ${record.fieldName},');
    }
    buffer.writeln('  }) {');
    buffer.writeln('    final newConditions = [..._where];');
    for (final record in fields) {
      buffer.writeln('    if (${record.fieldName} != null) ');
      buffer.writeln('      newConditions.add(${record.fieldName});');
    }
    buffer.writeln(
      '    return ${capitalize(tableName)}UpdateBuilder(db, where: newConditions,',
    );
    for (final record in fields) {
      buffer.writeln('      ${record.fieldName}: _${record.fieldName},');
    }
    buffer.writeln(');');
    buffer.writeln('  }');
    buffer.writeln();
    buffer.writeln('  @override');
    buffer.writeln('  Future<int> execute() {');
    buffer.writeln();
    buffer.writeln('    // SET句の構築');
    buffer.writeln('    final updates = <String>[];');
    buffer.writeln('    final params = <String, dynamic>{};');
    for (final record in fields) {
      buffer.writeln('    if (_${record.fieldName} != null) {');
      buffer.writeln(
        "      updates.add('${record.columnName} = :set_${record.columnName}');",
      );
      buffer.writeln(
        '      params[\'set_${record.columnName}\'] = _${record.fieldName};',
      );
      buffer.writeln('    }');
    }
    buffer.writeln();
    buffer.writeln(
      '    if (updates.isEmpty) throw StateError(\'No fields to update\');',
    );
    buffer.writeln();
    buffer.writeln(
      "    final sqlBuffer = StringBuffer('UPDATE $tableName SET \${updates.join(', ')}');",
    );
    buffer.writeln();
    buffer.writeln('    // WHERE句の構築');
    buffer.writeln('    if (_where.isNotEmpty) {');
    buffer.writeln("      sqlBuffer.write(' WHERE ');");
    buffer.writeln('      final whereClauses = <String>[];');
    buffer.writeln('      for (var i = 0; i < _where.length; i++) {');
    buffer.writeln('        final condition = _where[i];');
    buffer.writeln('        whereClauses.add(condition.toSql(i));');
    buffer.writeln('        params.addAll(condition.toParams(i));');
    buffer.writeln('      }');
    buffer.writeln("      sqlBuffer.write(whereClauses.join(' AND '));");
    buffer.writeln('    }');
    buffer.writeln();
    buffer.writeln(
      '    return db.execute(sqlBuffer.toString(), params: params);',
    );
    buffer.writeln('  }');
    buffer.writeln('}');
    buffer.writeln();
  }

  void generateDeleteBuilder(
    StringBuffer buffer,
    String tableName,
    List<AnalyzedField> fields,
  ) {
    buffer.writeln(
      'class ${capitalize(tableName)}DeleteBuilder extends QueryFuture<int> with FutureMixin<int> {',
    );
    buffer.writeln('  final PostgresQueryable db;');
    buffer.writeln('  final List<Condition> _where;');
    buffer.writeln();
    buffer.writeln(
      '  ${capitalize(tableName)}DeleteBuilder(this.db, [List<Condition>? where]) : _where = where ?? [];',
    );
    buffer.writeln();
    buffer.writeln('  // WHERE句（SelectBuilderと同じ仕組み）');
    buffer.writeln('  ${capitalize(tableName)}DeleteBuilder where({');
    for (final record in fields) {
      buffer.writeln('    Condition? ${record.fieldName},');
    }
    buffer.writeln('  }) {');
    buffer.writeln('    final newConditions = [..._where];');
    for (final record in fields) {
      buffer.writeln('    if (${record.fieldName} != null) ');
      buffer.writeln('      newConditions.add(${record.fieldName});');
    }
    buffer.writeln(
      '    return ${capitalize(tableName)}DeleteBuilder(db, newConditions);',
    );
    buffer.writeln('  }');
    buffer.writeln();
    buffer.writeln('  @override');
    buffer.writeln('  Future<int> execute() {');
    buffer.writeln(
      "    final sqlBuffer = StringBuffer('DELETE FROM $tableName');",
    );
    buffer.writeln('    final params = <String, dynamic>{};');
    buffer.writeln();
    buffer.writeln('    // WHERE句の構築');
    buffer.writeln('    if (_where.isNotEmpty) {');
    buffer.writeln("      sqlBuffer.write(' WHERE ');");
    buffer.writeln('      final whereClauses = <String>[];');
    buffer.writeln('      for (var i = 0; i < _where.length; i++) {');
    buffer.writeln('        final condition = _where[i];');
    buffer.writeln('        whereClauses.add(condition.toSql(i));');
    buffer.writeln('        params.addAll(condition.toParams(i));');
    buffer.writeln('      }');
    buffer.writeln("      sqlBuffer.write(whereClauses.join(' AND '));");
    buffer.writeln('    }');
    buffer.writeln();
    buffer.writeln(
      '    return db.execute(sqlBuffer.toString(), params: params);',
    );
    buffer.writeln('  }');
    buffer.writeln('}');
    buffer.writeln();
  }

  void generateRelationSelectBuilder(
    StringBuffer buffer,
    String tableName,
    List<AnalyzedField> fields,
    Map<String, List<AnalyzedField>> allTables,
  ) {
    // FK を持つフィールドを抽出
    final fkFields =
        fields.where((f) => f.refTable != null && f.refColumn != null).toList();

    if (fkFields.isEmpty) return;

    // 全ての FK の部分集合を生成（組み合わせ爆発対応）
    final subsets = _generateSubsets(fkFields);

    for (final subset in subsets) {
      if (subset.isEmpty) continue; // 空集合はスキップ（元の SelectBuilder）

      _generateRelationBuilderForSubset(
        buffer,
        tableName,
        fields,
        fkFields,
        subset,
        allTables,
      );
    }
  }

  /// FK フィールドの全部分集合を生成
  List<List<AnalyzedField>> _generateSubsets(List<AnalyzedField> fields) {
    final result = <List<AnalyzedField>>[];
    final n = fields.length;

    for (var i = 0; i < (1 << n); i++) {
      final subset = <AnalyzedField>[];
      for (var j = 0; j < n; j++) {
        if ((i & (1 << j)) != 0) {
          subset.add(fields[j]);
        }
      }
      result.add(subset);
    }

    return result;
  }

  /// テーブル名を単数形に変換
  /// 例: 'posts' -> 'post', 'users' -> 'user', 'status' -> 'status'
  String _toSingular(String name) {
    // 'ss' で終わる場合はそのまま（status, class, etc.）
    if (name.endsWith('ss')) return name;
    // 'ies' で終わる場合は 'y' に（categories -> category）
    if (name.endsWith('ies')) return '${name.substring(0, name.length - 3)}y';
    // 's' で終わる場合は削除（posts -> post, users -> user）
    if (name.endsWith('s')) return name.substring(0, name.length - 1);
    return name;
  }

  /// FK フィールド名からリレーション名を推測
  /// 例: 'userId' -> 'user', 'postStatusId' -> 'postStatus'
  String _inferRelationName(String fieldName, String refTable) {
    // 'userId' -> 'user'
    if (fieldName.endsWith('Id')) {
      return fieldName.substring(0, fieldName.length - 2);
    }
    // フォールバック: 参照先テーブル名をそのまま使う
    return refTable;
  }

  /// 部分集合のサフィックスを生成
  /// 例: [userId, statusId] -> 'WithUserWithStatus'
  String _generateSubsetSuffix(List<AnalyzedField> subset) {
    return subset.map((fk) {
      final relationName = _inferRelationName(fk.fieldName, fk.refTable!);
      return 'With${capitalize(relationName)}';
    }).join('');
  }

  void _generateRelationBuilderForSubset(
    StringBuffer buffer,
    String tableName,
    List<AnalyzedField> allFields,
    List<AnalyzedField> allFkFields,
    List<AnalyzedField> includedFks,
    Map<String, List<AnalyzedField>> allTables,
  ) {
    final tableCapitalized = capitalize(tableName);
    final suffix = _generateSubsetSuffix(includedFks);
    final builderName = '$tableCapitalized${suffix}SelectBuilder';
    final configName = '$tableCapitalized${suffix}SelectConfig';
    final rowName = '$tableCapitalized${suffix}Row';

    // 残りの FK（まだ include されていないもの）
    final remainingFks =
        allFkFields.where((fk) => !includedFks.contains(fk)).toList();

    // Row typedef を生成
    _generateRelationRowTypedef(
        buffer, tableName, rowName, includedFks, allTables);

    // Config クラスを生成
    _generateRelationSelectConfig(buffer, configName);

    // SelectBuilder クラスを生成
    _generateRelationSelectBuilderClass(
      buffer,
      tableName,
      builderName,
      configName,
      rowName,
      allFields,
      allFkFields,
      includedFks,
      remainingFks,
      allTables,
    );
  }

  void _generateRelationRowTypedef(
    StringBuffer buffer,
    String tableName,
    String rowName,
    List<AnalyzedField> includedFks,
    Map<String, List<AnalyzedField>> allTables,
  ) {
    buffer.writeln('typedef $rowName = ({');
    buffer.writeln('  ${capitalize(tableName)}Row ${_toSingular(tableName).toLowerCase()},');

    for (final fk in includedFks) {
      final relationName = _inferRelationName(fk.fieldName, fk.refTable!);
      final refTableCapitalized = capitalize(fk.refTable!);
      final nullableSuffix = fk.isNullable ? '?' : '';
      buffer.writeln('  ${refTableCapitalized}Row$nullableSuffix $relationName,');
    }

    buffer.writeln('});');
    buffer.writeln();
  }

  void _generateRelationSelectConfig(StringBuffer buffer, String configName) {
    buffer.writeln('class $configName {');
    buffer.writeln('  final List<Condition> where;');
    buffer.writeln('  final int? limit;');
    buffer.writeln('  final int? offset;');
    buffer.writeln();
    buffer.writeln('  $configName({');
    buffer.writeln('    required List<Condition>? where,');
    buffer.writeln('    required this.limit,');
    buffer.writeln('    required this.offset,');
    buffer.writeln('  }) : where = where ?? [];');
    buffer.writeln('}');
    buffer.writeln();
  }

  void _generateRelationSelectBuilderClass(
    StringBuffer buffer,
    String tableName,
    String builderName,
    String configName,
    String rowName,
    List<AnalyzedField> allFields,
    List<AnalyzedField> allFkFields,
    List<AnalyzedField> includedFks,
    List<AnalyzedField> remainingFks,
    Map<String, List<AnalyzedField>> allTables,
  ) {
    buffer.writeln(
      'class $builderName extends QueryFuture<List<$rowName>> with FutureMixin<List<$rowName>> {',
    );
    buffer.writeln('  final PostgresQueryable db;');
    buffer.writeln('  final $configName config;');
    buffer.writeln();
    buffer.writeln('  $builderName(this.db, this.config);');
    buffer.writeln();

    // execute() メソッド
    _generateRelationExecuteMethod(
      buffer,
      tableName,
      rowName,
      allFields,
      includedFks,
      allTables,
    );

    // 残りの FK に対する withXxx() メソッド
    for (final fk in remainingFks) {
      _generateWithMethod(
        buffer,
        tableName,
        allFkFields,
        includedFks,
        fk,
      );
    }

    // where() メソッド
    _generateRelationWhereMethod(buffer, builderName, configName, allFields);

    // limit() メソッド
    _generateRelationLimitMethod(buffer, builderName, configName);

    // offset() メソッド
    _generateRelationOffsetMethod(buffer, builderName, configName);

    buffer.writeln('}');
    buffer.writeln();
  }

  void _generateRelationExecuteMethod(
    StringBuffer buffer,
    String tableName,
    String rowName,
    List<AnalyzedField> allFields,
    List<AnalyzedField> includedFks,
    Map<String, List<AnalyzedField>> allTables,
  ) {
    buffer.writeln('  @override');
    buffer.writeln('  Future<List<$rowName>> execute() {');

    // SELECT句を構築（エイリアス付き）
    final selectColumns = <String>[];

    // メインテーブルのカラム
    for (final field in allFields) {
      selectColumns.add('$tableName.${field.columnName} AS ${tableName}_${field.columnName}');
    }

    // 参照先テーブルのカラム
    for (final fk in includedFks) {
      final refTable = fk.refTable!;
      final refFields = allTables[refTable];
      if (refFields != null) {
        for (final refField in refFields) {
          selectColumns.add('$refTable.${refField.columnName} AS ${refTable}_${refField.columnName}');
        }
      }
    }

    buffer.writeln("    final sqlBuffer = StringBuffer('SELECT ${selectColumns.join(', ')} FROM $tableName');");

    // JOIN句
    for (final fk in includedFks) {
      final refTable = fk.refTable!;
      final refColumn = fk.refColumn!;
      final joinType = fk.isNullable ? 'LEFT' : 'INNER';
      buffer.writeln(
        "    sqlBuffer.write(' $joinType JOIN $refTable ON $tableName.${fk.columnName} = $refTable.$refColumn');",
      );
    }

    // WHERE句
    buffer.writeln('    final params = <String, dynamic>{};');
    buffer.writeln('    if (config.where.isNotEmpty) {');
    buffer.writeln("      sqlBuffer.write(' WHERE ');");
    buffer.writeln('      final whereClauses = <String>[];');
    buffer.writeln('      for (var i = 0; i < config.where.length; i++) {');
    buffer.writeln('        final condition = config.where[i];');
    buffer.writeln('        whereClauses.add(condition.toSql(i));');
    buffer.writeln('        params.addAll(condition.toParams(i));');
    buffer.writeln('      }');
    buffer.writeln("      sqlBuffer.write(whereClauses.join(' AND '));");
    buffer.writeln('    }');

    // LIMIT / OFFSET
    buffer.writeln('    if (config.limit != null) {');
    buffer.writeln("      sqlBuffer.write(' LIMIT \${config.limit}');");
    buffer.writeln('    }');
    buffer.writeln('    if (config.offset != null) {');
    buffer.writeln("      sqlBuffer.write(' OFFSET \${config.offset}');");
    buffer.writeln('    }');

    // クエリ実行と結果マッピング
    buffer.writeln('    return db.query(sqlBuffer.toString(), params: params).then((result) {');
    buffer.writeln('      return result.map((row) {');
    buffer.writeln('        return (');

    // メインテーブルの Row
    buffer.writeln('          ${_toSingular(tableName).toLowerCase()}: (');
    for (final field in allFields) {
      final alias = '${tableName}_${field.columnName}';
      _generateFieldMapping(buffer, field, alias, '            ');
    }
    buffer.writeln('          ),');

    // 参照先テーブルの Row
    for (final fk in includedFks) {
      final relationName = _inferRelationName(fk.fieldName, fk.refTable!);
      final refTable = fk.refTable!;
      final refFields = allTables[refTable];

      if (fk.isNullable) {
        // Nullable FK: LEFT JOIN の結果が null の場合を考慮
        final firstRefField = refFields?.first;
        final checkAlias = '${refTable}_${firstRefField?.columnName ?? 'id'}';
        buffer.writeln("          $relationName: row['$checkAlias'] == null ? null : (");
      } else {
        buffer.writeln('          $relationName: (');
      }

      if (refFields != null) {
        for (final refField in refFields) {
          final alias = '${refTable}_${refField.columnName}';
          _generateFieldMapping(buffer, refField, alias, '            ');
        }
      }
      buffer.writeln('          ),');
    }

    buffer.writeln('        );');
    buffer.writeln('      }).toList();');
    buffer.writeln('    });');
    buffer.writeln('  }');
    buffer.writeln();
  }

  void _generateFieldMapping(
    StringBuffer buffer,
    AnalyzedField field,
    String alias,
    String indent,
  ) {
    switch (field.columnMapper) {
      case PgColumnMapper.integer:
      case PgColumnMapper.serial:
        buffer.writeln(
          "$indent${field.fieldName}: row['$alias'] as int${field.isNullable ? '?' : ''},",
        );
      case PgColumnMapper.varchar:
      case PgColumnMapper.text:
      case PgColumnMapper.uuid:
        buffer.writeln(
          "$indent${field.fieldName}: row['$alias'] as String${field.isNullable ? '?' : ''},",
        );
      case PgColumnMapper.timestamp:
        buffer.writeln(
          "$indent${field.fieldName}: row['$alias'] as DateTime${field.isNullable ? '?' : ''},",
        );
      case PgColumnMapper.jsonb:
        buffer.writeln(
          "$indent${field.fieldName}: row['$alias'] as Map<String, dynamic>${field.isNullable ? '?' : ''},",
        );
      case PgColumnMapper.unknown:
        buffer.writeln("$indent${field.fieldName}: row['$alias'],");
    }
  }

  void _generateWithMethod(
    StringBuffer buffer,
    String tableName,
    List<AnalyzedField> allFkFields,
    List<AnalyzedField> currentFks,
    AnalyzedField newFk,
  ) {
    final relationName = _inferRelationName(newFk.fieldName, newFk.refTable!);

    // 新しいFKリストを作成し、元のFK順序でソート
    final newFks = [...currentFks, newFk];
    newFks.sort((a, b) {
      final indexA = allFkFields.indexOf(a);
      final indexB = allFkFields.indexOf(b);
      return indexA.compareTo(indexB);
    });

    final newSuffix = _generateSubsetSuffix(newFks);
    final newBuilderName = '${capitalize(tableName)}${newSuffix}SelectBuilder';
    final newConfigName = '${capitalize(tableName)}${newSuffix}SelectConfig';

    buffer.writeln('  $newBuilderName with${capitalize(relationName)}() {');
    buffer.writeln('    return $newBuilderName(');
    buffer.writeln('      db,');
    buffer.writeln('      $newConfigName(');
    buffer.writeln('        where: config.where,');
    buffer.writeln('        limit: config.limit,');
    buffer.writeln('        offset: config.offset,');
    buffer.writeln('      ),');
    buffer.writeln('    );');
    buffer.writeln('  }');
    buffer.writeln();
  }

  void _generateRelationWhereMethod(
    StringBuffer buffer,
    String builderName,
    String configName,
    List<AnalyzedField> fields,
  ) {
    buffer.writeln('  $builderName where({');
    for (final field in fields) {
      buffer.writeln('    Condition? ${field.fieldName},');
    }
    buffer.writeln('  }) {');
    buffer.writeln('    final newConditions = [...config.where];');
    for (final field in fields) {
      buffer.writeln('    if (${field.fieldName} != null) newConditions.add(${field.fieldName});');
    }
    buffer.writeln('    return $builderName(');
    buffer.writeln('      db,');
    buffer.writeln('      $configName(');
    buffer.writeln('        where: newConditions,');
    buffer.writeln('        limit: config.limit,');
    buffer.writeln('        offset: config.offset,');
    buffer.writeln('      ),');
    buffer.writeln('    );');
    buffer.writeln('  }');
    buffer.writeln();
  }

  void _generateRelationLimitMethod(
    StringBuffer buffer,
    String builderName,
    String configName,
  ) {
    buffer.writeln('  $builderName limit(int limit) {');
    buffer.writeln('    return $builderName(');
    buffer.writeln('      db,');
    buffer.writeln('      $configName(');
    buffer.writeln('        where: config.where,');
    buffer.writeln('        limit: limit,');
    buffer.writeln('        offset: config.offset,');
    buffer.writeln('      ),');
    buffer.writeln('    );');
    buffer.writeln('  }');
    buffer.writeln();
  }

  void _generateRelationOffsetMethod(
    StringBuffer buffer,
    String builderName,
    String configName,
  ) {
    buffer.writeln('  $builderName offset(int offset) {');
    buffer.writeln('    return $builderName(');
    buffer.writeln('      db,');
    buffer.writeln('      $configName(');
    buffer.writeln('        where: config.where,');
    buffer.writeln('        limit: config.limit,');
    buffer.writeln('        offset: offset,');
    buffer.writeln('      ),');
    buffer.writeln('    );');
    buffer.writeln('  }');
  }

  AnalyzedField analyzeField(String fieldName, Expression expression) {
    bool isPrimaryKey = false;
    bool isUnique = false;
    bool isNullable = false;
    bool hasDefault = false;
    String? columnType;
    String? columnName;
    PgColumnMapper? columnMapper;
    String? returnType;
    int? varcharLength;
    String? refTable;
    String? refColumn;

    // メソッドチェーンを全部集める
    final methods = <MethodInvocation>[];
    Expression? current = expression;
    while (current is MethodInvocation) {
      methods.add(current);
      current = current.target;
    }

    // 逆順（起点から）で解析
    for (final method in methods.reversed) {
      final methodName = method.methodName.name;

      final column = PgColumnMapper.match(methodName);
      if (column != null) {
        columnMapper = column;
        columnType = column.name;
        returnType = column.dartType;

        // 第一引数からカラム名を取得
        if (method.argumentList.arguments.isNotEmpty) {
          final firstArg = method.argumentList.arguments.first;
          if (firstArg is SimpleStringLiteral) {
            columnName = firstArg.value; // 'created_at' を取得
          }
        }

        // varcharの場合、名前付きパラメータ 'length' を取得
        if (methodName == 'varchar') {
          for (final arg in method.argumentList.arguments) {
            if (arg is NamedArgument && arg.name.lexeme == 'length') {
              if (arg.argumentExpression is IntegerLiteral) {
                varcharLength = (arg.argumentExpression as IntegerLiteral).value;
              }
            }
          }
        }
      } else if (methodName == 'primaryKey') {
        isPrimaryKey = true;
      } else if (methodName == 'unique') {
        isUnique = true;
      } else if (methodName == 'nullable') {
        isNullable = true;
      } else if (methodName == 'withDefault' ||
          methodName == 'withDefaultNow') {
        hasDefault = true;
      } else if (methodName == 'references') {
        for (final arg in method.argumentList.arguments) {
          if (arg is FunctionExpression) {
            final body = arg.body;
            if (body is ExpressionFunctionBody) {
              final refExpr = body.expression;
              if (refExpr is PropertyAccess) {
                refTable = refExpr.target.toString();
                refColumn = refExpr.propertyName.name;
              }
              if (refExpr is PrefixedIdentifier) {
                refTable = refExpr.prefix.name;
                refColumn = refExpr.identifier.name;
              }
            }
          }
        }
      }
    }

    return (
      fieldName: fieldName,
      columnType: columnType ?? 'unknown',
      columnName: columnName ?? fieldName,
      returnType: returnType ?? 'dynamic',
      columnMapper: columnMapper ?? PgColumnMapper.unknown,
      isPrimaryKey: isPrimaryKey,
      isUnique: isUnique,
      isNullable: isNullable,
      hasDefault: hasDefault,
      varcharLength: varcharLength,
      refTable: refTable,
      refColumn: refColumn,
    );
  }

  /// Phase 1で収集された全テーブル情報をJSONファイルから読み込む
  Future<Map<String, List<AnalyzedField>>> _readAllTableInfo(
    BuildStep buildStep,
  ) async {
    final allTables = <String, List<AnalyzedField>>{};

    await for (final input
        in buildStep.findAssets(Glob('**/*.aim_tables.json'))) {
      try {
        final content = await buildStep.readAsString(input);
        final tables = jsonDecode(content) as Map<String, dynamic>;

        for (final entry in tables.entries) {
          final tableVarName = entry.key;
          final tableData = entry.value as Map<String, dynamic>;
          final fieldsJson = tableData['fields'] as List<dynamic>;

          final fields = fieldsJson.map((fieldJson) {
            final f = fieldJson as Map<String, dynamic>;
            return (
              fieldName: f['fieldName'] as String,
              columnType: f['columnType'] as String,
              columnName: f['columnName'] as String,
              returnType: f['returnType'] as String,
              columnMapper: PgColumnMapper.match(f['columnType'] as String) ??
                  PgColumnMapper.unknown,
              isPrimaryKey: f['isPrimaryKey'] as bool,
              isUnique: f['isUnique'] as bool,
              isNullable: f['isNullable'] as bool,
              // Not collected into the cross-file JSON: these fields are
              // only read for foreign-key lookups, never for insert
              // generation, so the database-fills check never needs it here.
              hasDefault: false,
              varcharLength: f['varcharLength'] as int?,
              refTable: f['refTable'] as String?,
              refColumn: f['refColumn'] as String?,
            );
          }).toList();

          allTables[tableVarName] = fields;
        }
      } catch (_) {
        // Skip files that can't be read or parsed
      }
    }

    return allTables;
  }
}

typedef AnalyzedField = ({
  String fieldName,
  String columnType, // 'integer', 'varchar' など
  String columnName,
  String returnType, // 'int', 'String' など
  PgColumnMapper columnMapper,
  bool isPrimaryKey,
  bool isUnique,
  bool isNullable,
  bool hasDefault,
  int? varcharLength,
  String? refTable,
  String? refColumn,
});

class RecordVisitor extends RecursiveAstVisitor<void> {
  final String targetName;
  RecordLiteral? foundRecord;

  RecordVisitor(this.targetName);

  @override
  void visitTopLevelVariableDeclaration(TopLevelVariableDeclaration node) {
    for (final variable in node.variables.variables) {
      if (variable.name.lexeme == targetName) {
        if (variable.initializer is RecordLiteral) {
          foundRecord = variable.initializer as RecordLiteral;
        }
      }
    }
    super.visitTopLevelVariableDeclaration(node);
  }
}

String capitalize(String s) {
  if (s.isEmpty) return s;
  return s[0].toUpperCase() + s.substring(1);
}

enum PgColumnMapper {
  integer('int'),
  varchar('String'),
  text('String'),
  timestamp('DateTime'),
  serial('int'),
  jsonb('Map<String, dynamic>'),
  uuid('String'),
  unknown('dynamic');

  // 未対応（共通カラム型 - aim_orm）
  // bigint('int'),           // BIGINT - 大きな整数
  // smallint('int'),         // SMALLINT - 小さな整数
  // decimal('double'),       // DECIMAL/NUMERIC - 精密な数値（金額など）
  // double('double'),        // DOUBLE PRECISION/FLOAT
  // boolean('bool'),         // BOOLEAN/BOOL
  // date('DateTime'),        // DATE - 日付のみ
  // time('Duration'),        // TIME - 時刻のみ
  // blob('Uint8List'),       // BYTEA/BLOB - バイナリデータ
  // json('Map<String, dynamic>'), // JSON

  // 未対応（PostgreSQL固有 - aim_orm_postgres）
  // bigserial('int'),        // BIGSERIAL
  // timestamptz('DateTime'), // TIMESTAMP WITH TIME ZONE
  // timetz('Duration'),      // TIME WITH TIME ZONE
  // array('List<dynamic>'),  // ARRAY[]
  // inet('String'),          // INET - IPアドレス
  // cidr('String'),          // CIDR
  // macaddr('String'),       // MACADDR
  // money('double'),         // MONEY
  // xml('String'),           // XML
  // hstore('Map<String, String>'), // HSTORE

  final String dartType;

  const PgColumnMapper(this.dartType);

  static String? toDartType(String columnType) {
    for (final mapper in PgColumnMapper.values) {
      if (mapper.name == columnType) {
        return mapper.dartType;
      }
    }
    return null;
  }

  static PgColumnMapper? match(String value) {
    for (final mapper in PgColumnMapper.values) {
      if (mapper.name == value) {
        return mapper;
      }
    }
    return null;
  }
}
