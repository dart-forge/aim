import 'dart:convert';
import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:aim_orm/aim_orm.dart';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

class DbGenerateCommand extends Command<void> {
  @override
  final name = 'db:generate';

  @override
  final description = 'Generate migration from table definitions';

  DbGenerateCommand() {
    argParser.addOption(
      'path',
      abbr: 'p',
      help: 'Path to schema definitions (default: lib/schema)',
      defaultsTo: 'lib/schema',
    );
    argParser.addOption(
      'name',
      abbr: 'n',
      help: 'Migration file name (e.g., add_users_table)',
    );
  }

  @override
  Future<void> run() async {
    // pubspec.yaml を読み込む
    final pubspecFile = File('pubspec.yaml');
    if (!await pubspecFile.exists()) {
      print('Error: pubspec.yaml not found');
      print('Please run from the root directory of an Aim project');
      exit(1);
    }

    final pubspecContent = await pubspecFile.readAsString();

    // schema パスを決定（CLI オプション > pubspec.yaml > デフォルト）
    String schemaPath = argResults?['path'] as String;
    if (schemaPath == 'lib/schema') {
      // デフォルト値の場合、pubspec.yaml を確認
      final pubspecSchemaPath = _extractAimSchema(pubspecContent);
      if (pubspecSchemaPath != null) {
        schemaPath = pubspecSchemaPath;
      }
    }

    final absolutePath = path.absolute(schemaPath);

    // ディレクトリ or ファイル存在確認
    final entityType = FileSystemEntity.typeSync(absolutePath);
    if (entityType == FileSystemEntityType.notFound) {
      print('Error: Schema path not found: $schemaPath');
      print('Create the directory/file or specify a different path with --path');
      exit(1);
    }

    print('📦 Scanning table definitions in $schemaPath...');

    // 1. Dart ファイルを解析してスキーマ情報を収集
    final currentSchema = await _analyzeSchema(absolutePath);

    print('Found ${currentSchema.tables.length} tables');

    // 2. 前回の schema.json を読み込む
    final schemaFile = File('db/schema.json');
    Schema? previousSchema;
    if (await schemaFile.exists()) {
      final content = await schemaFile.readAsString();
      previousSchema = Schema.fromJson(jsonDecode(content));
    }

    // 3. 差分を計算
    final diff = _calculateDiff(previousSchema, currentSchema);

    if (diff.isEmpty) {
      print('✅ No changes detected');
      return;
    }

    // 3.5. カラムリネームの検出（同じテーブルでDROP+ADDがある場合）
    final renamedDiffs = await _detectRenames(diff);

    // 3.6. 危険なADD COLUMNをチェック（NOT NULL + DEFAULTなし）
    final dangerousAddColumns = renamedDiffs.where((d) =>
        d.type == _DiffType.addColumn &&
        d.column != null &&
        !d.column!.isNullable &&
        d.column!.defaultValue == null);

    if (dangerousAddColumns.isNotEmpty) {
      print('');
      print('⚠️  Warning: The following columns are NOT NULL without DEFAULT:');
      for (final d in dangerousAddColumns) {
        print('   - ${d.table.name}.${d.column!.name}');
      }
      print('');
      print('This will fail if the table already has data.');
      print('Consider adding .nullable() or .withDefault(...) to these columns.');
      print('');
      stdout.write('Continue anyway? [y/N]: ');

      final input = stdin.readLineSync()?.toLowerCase() ?? '';
      if (input != 'y' && input != 'yes') {
        print('Aborted.');
        return;
      }
      print('');
    }

    // 4. マイグレーション SQL を生成
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(RegExp(r'[:\-T.]'), '')
        .substring(0, 14);
    final nameOption = argResults?['name'] as String?;
    final suffix = nameOption != null ? _toSnakeCase(nameOption) : 'migration';
    final migrationName = '${timestamp}_$suffix.sql';
    final migrationFile = File('db/migrations/$migrationName');

    await migrationFile.parent.create(recursive: true);
    await migrationFile.writeAsString(_generateMigrationFile(renamedDiffs));

    print('📝 Generated: db/migrations/$migrationName');

    // 5. 新しい schema.json を保存
    await schemaFile.parent.create(recursive: true);
    await schemaFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(currentSchema.toJson()),
    );

    print('💾 Updated: db/schema.json');
    print('✅ Done!');
  }

  Future<Schema> _analyzeSchema(String tablesPath) async {
    final tables = <TableSchema>[];

    final collection = AnalysisContextCollection(
      includedPaths: [tablesPath],
    );

    for (final context in collection.contexts) {
      for (final filePath in context.contextRoot.analyzedFiles()) {
        if (!filePath.endsWith('.dart')) continue;

        final result = await context.currentSession.getResolvedUnit(filePath);
        if (result is! ResolvedUnitResult) continue;

        final unit = result.unit;

        // TopLevelVariableDeclaration を探す
        for (final decl in unit.declarations) {
          if (decl is! TopLevelVariableDeclaration) continue;

          // @PgTable アノテーションを探す
          for (final annotation in decl.metadata) {
            if (annotation.name.name != 'PgTable') continue;

            // テーブル名を取得
            final args = annotation.arguments?.arguments;
            if (args == null || args.isEmpty) continue;

            final tableNameArg = args.first;
            if (tableNameArg is! SimpleStringLiteral) continue;
            final tableName = tableNameArg.value;

            // Record のフィールドを解析
            for (final variable in decl.variables.variables) {
              final initializer = variable.initializer;
              if (initializer is! RecordLiteral) continue;

              final columns = <ColumnSchema>[];
              final indexes = <IndexSchema>[];
              final foreignKeys = <ForeignKeySchema>[];

              for (final field in initializer.fields) {
                if (field is! RecordLiteralNamedField) continue;

                final fieldName = field.name.lexeme;
                final columnInfo = _analyzeColumn(
                  fieldName,
                  field.fieldExpression,
                  filePath,
                );

                columns.add(columnInfo.column);
                if (columnInfo.isIndexed) {
                  indexes.add(IndexSchema(columns: [columnInfo.column.name]));
                }
                if (columnInfo.foreignKey != null) {
                  foreignKeys.add(columnInfo.foreignKey!);
                }
              }

              tables.add(TableSchema(
                name: tableName,
                columns: columns,
                indexes: indexes,
                foreignKeys: foreignKeys,
              ));
            }
          }
        }
      }
    }

    return Schema(tables: tables);
  }

  _ColumnAnalysisResult _analyzeColumn(
    String fieldName,
    Expression expr,
    String filePath,
  ) {
    String? columnName;
    String columnType = 'unknown';
    bool isPrimaryKey = false;
    bool isUnique = false;
    bool isNullable = false;
    bool isIndexed = false;
    int? varcharLength;
    String? defaultValue;
    ForeignKeySchema? foreignKey;

    // メソッドチェーンを収集
    final methods = <MethodInvocation>[];
    Expression? current = expr;
    while (current is MethodInvocation) {
      methods.add(current);
      current = current.target;
    }

    // 逆順で解析（起点から）
    for (final method in methods.reversed) {
      final methodName = method.methodName.name;

      switch (methodName) {
        case 'integer':
        case 'varchar':
        case 'text':
        case 'timestamp':
        case 'uuid':
        case 'serial':
        case 'jsonb':
          columnType = methodName;
          // 第一引数からカラム名
          final args = method.argumentList.arguments;
          if (args.isNotEmpty && args.first is SimpleStringLiteral) {
            columnName = (args.first as SimpleStringLiteral).value;
          }
          // varchar の length
          if (methodName == 'varchar') {
            for (final arg in args) {
              if (arg is NamedArgument && arg.name.lexeme == 'length') {
                if (arg.argumentExpression is IntegerLiteral) {
                  varcharLength = (arg.argumentExpression as IntegerLiteral).value;
                }
              }
            }
          }
        case 'primaryKey':
          isPrimaryKey = true;
        case 'unique':
          isUnique = true;
        case 'nullable':
          isNullable = true;
        case 'indexed':
          isIndexed = true;
        case 'withDefault':
          // withDefault(DateTime.now()) or withDefault('value') etc.
          final args = method.argumentList.arguments;
          if (args.isNotEmpty) {
            defaultValue = _extractDefaultValue(args.first.argumentExpression);
          }
        case 'references':
          // references(() => users.id, onDelete: OnDeleteAction.cascade)
          final args = method.argumentList.arguments;
          if (args.isNotEmpty) {
            final firstArg = args.first;
            if (firstArg is FunctionExpression) {
              final body = firstArg.body;
              if (body is ExpressionFunctionBody) {
                final refExpr = body.expression;
                String? refTable;
                String? refColumn;
                // PropertyAccess: users.id
                if (refExpr is PropertyAccess) {
                  final target = refExpr.target;
                  if (target is SimpleIdentifier) {
                    refTable = target.name;
                  }
                  refColumn = refExpr.propertyName.name;
                }
                // PrefixedIdentifier: users.id (fallback)
                if (refExpr is PrefixedIdentifier) {
                  refTable = refExpr.prefix.name;
                  refColumn = refExpr.identifier.name;
                }
                if (refTable != null && refColumn != null) {
                  foreignKey = ForeignKeySchema(
                    column: columnName ?? fieldName,
                    referencesTable: refTable,
                    referencesColumn: refColumn,
                    onDelete: _extractOnDelete(args, filePath),
                    onUpdate: _extractOnUpdate(args, filePath),
                  );
                }
              }
            }
          }
      }
    }

    return _ColumnAnalysisResult(
      column: ColumnSchema(
        name: columnName ?? fieldName,
        type: columnType,
        isPrimaryKey: isPrimaryKey,
        isUnique: isUnique,
        isNullable: isNullable,
        varcharLength: varcharLength,
        defaultValue: defaultValue,
      ),
      isIndexed: isIndexed,
      foreignKey: foreignKey,
    );
  }

  String? _extractDefaultValue(Expression expr) {
    // DateTime.now() → CURRENT_TIMESTAMP
    final exprStr = expr.toString();
    if (exprStr == 'DateTime.now()') {
      return 'CURRENT_TIMESTAMP';
    }
    // 文字列リテラル
    if (expr is SimpleStringLiteral) {
      return "'${expr.value}'";
    }
    // 数値リテラル
    if (expr is IntegerLiteral) {
      return expr.value.toString();
    }
    if (expr is DoubleLiteral) {
      return expr.value.toString();
    }
    // boolリテラル
    if (expr is BooleanLiteral) {
      return expr.value ? 'TRUE' : 'FALSE';
    }
    // それ以外は「デフォルトがある」ことだけ記録
    return _hasDefaultSentinel;
  }

  String? _extractOnDelete(NodeList<Argument> args, String filePath) {
    final name = _extractActionName(args, 'onDelete');
    if (name == null) return null;
    if (!OnDeleteAction.values.any((action) => action.name == name)) {
      throw FormatException(
        'Unknown onDelete action "$name" in $filePath',
      );
    }
    return name;
  }

  String? _extractOnUpdate(NodeList<Argument> args, String filePath) {
    final name = _extractActionName(args, 'onUpdate');
    if (name == null) return null;
    if (!OnUpdateAction.values.any((action) => action.name == name)) {
      throw FormatException(
        'Unknown onUpdate action "$name" in $filePath',
      );
    }
    return name;
  }

  /// Pulls the identifier name out of a named argument like
  /// `onDelete: OnDeleteAction.setNull`, without checking whether it is a
  /// value the enum actually declares.
  String? _extractActionName(NodeList<Argument> args, String argName) {
    for (final arg in args) {
      if (arg is NamedArgument && arg.name.lexeme == argName) {
        if (arg.argumentExpression is PrefixedIdentifier) {
          return (arg.argumentExpression as PrefixedIdentifier).identifier.name;
        }
      }
    }
    return null;
  }

  /// Resolves a stored `onDelete` action name back to its [OnDeleteAction]
  /// SQL keyword. The name was already validated in [_extractOnDelete], so
  /// this only fails if that validation was somehow bypassed.
  String _onDeleteKeyword(String name) {
    try {
      return OnDeleteAction.values.byName(name).sqlKeyword;
    } on ArgumentError {
      throw FormatException('Unknown onDelete action "$name"');
    }
  }

  /// Resolves a stored `onUpdate` action name back to its [OnUpdateAction]
  /// SQL keyword. The name was already validated in [_extractOnUpdate], so
  /// this only fails if that validation was somehow bypassed.
  String _onUpdateKeyword(String name) {
    try {
      return OnUpdateAction.values.byName(name).sqlKeyword;
    } on ArgumentError {
      throw FormatException('Unknown onUpdate action "$name"');
    }
  }

  List<_SchemaDiff> _calculateDiff(Schema? previous, Schema current) {
    final diffs = <_SchemaDiff>[];

    if (previous == null) {
      // 全部 CREATE TABLE
      for (final table in current.tables) {
        diffs.add(_SchemaDiff(type: _DiffType.createTable, table: table));
      }
      return diffs;
    }

    final prevTableMap = {for (final t in previous.tables) t.name: t};
    final currTableMap = {for (final t in current.tables) t.name: t};

    // 新規テーブル
    for (final table in current.tables) {
      if (!prevTableMap.containsKey(table.name)) {
        diffs.add(_SchemaDiff(type: _DiffType.createTable, table: table));
      }
    }

    // 削除テーブル
    for (final table in previous.tables) {
      if (!currTableMap.containsKey(table.name)) {
        diffs.add(_SchemaDiff(type: _DiffType.dropTable, table: table));
      }
    }

    // 既存テーブルのカラム差分
    for (final currTable in current.tables) {
      final prevTable = prevTableMap[currTable.name];
      if (prevTable == null) continue; // 新規テーブルはスキップ

      final prevColMap = {for (final c in prevTable.columns) c.name: c};
      final currColMap = {for (final c in currTable.columns) c.name: c};

      // 追加カラム
      for (final col in currTable.columns) {
        if (!prevColMap.containsKey(col.name)) {
          diffs.add(_SchemaDiff(
            type: _DiffType.addColumn,
            table: currTable,
            column: col,
          ));
        }
      }

      // 削除カラム
      for (final col in prevTable.columns) {
        if (!currColMap.containsKey(col.name)) {
          diffs.add(_SchemaDiff(
            type: _DiffType.dropColumn,
            table: currTable,
            column: col,
          ));
        }
      }

      // カラム変更（同名カラムの比較）
      for (final currCol in currTable.columns) {
        final prevCol = prevColMap[currCol.name];
        if (prevCol == null) continue; // 新規カラムはスキップ

        // 型変更
        final currType = _columnTypeSignature(currCol);
        final prevType = _columnTypeSignature(prevCol);
        if (currType != prevType) {
          diffs.add(_SchemaDiff(
            type: _DiffType.alterColumnType,
            table: currTable,
            column: currCol,
            oldColumn: prevCol,
          ));
        }

        // NOT NULL変更
        if (!prevCol.isNullable && currCol.isNullable) {
          diffs.add(_SchemaDiff(
            type: _DiffType.alterColumnDropNotNull,
            table: currTable,
            column: currCol,
          ));
        } else if (prevCol.isNullable && !currCol.isNullable) {
          diffs.add(_SchemaDiff(
            type: _DiffType.alterColumnSetNotNull,
            table: currTable,
            column: currCol,
          ));
        }

        // DEFAULT変更
        if (prevCol.defaultValue != currCol.defaultValue) {
          if (currCol.defaultValue == null) {
            diffs.add(_SchemaDiff(
              type: _DiffType.alterColumnDropDefault,
              table: currTable,
              column: currCol,
              oldColumn: prevCol,
            ));
          } else {
            diffs.add(_SchemaDiff(
              type: _DiffType.alterColumnSetDefault,
              table: currTable,
              column: currCol,
              oldColumn: prevCol,
            ));
          }
        }

        // UNIQUE変更
        if (!prevCol.isUnique && currCol.isUnique) {
          diffs.add(_SchemaDiff(
            type: _DiffType.addUnique,
            table: currTable,
            column: currCol,
          ));
        } else if (prevCol.isUnique && !currCol.isUnique) {
          diffs.add(_SchemaDiff(
            type: _DiffType.dropUnique,
            table: currTable,
            column: currCol,
          ));
        }
      }

      // 外部キー差分（column名をキーに比較）
      final prevFkMap = {for (final fk in prevTable.foreignKeys) fk.column: fk};
      final currFkMap = {for (final fk in currTable.foreignKeys) fk.column: fk};

      // 追加外部キー
      for (final fk in currTable.foreignKeys) {
        if (!prevFkMap.containsKey(fk.column)) {
          diffs.add(_SchemaDiff(
            type: _DiffType.addForeignKey,
            table: currTable,
            foreignKey: fk,
          ));
        }
      }

      // 削除外部キー
      for (final fk in prevTable.foreignKeys) {
        if (!currFkMap.containsKey(fk.column)) {
          diffs.add(_SchemaDiff(
            type: _DiffType.dropForeignKey,
            table: currTable,
            foreignKey: fk,
          ));
        }
      }

      // インデックス差分（カラムリストをキーに比較）
      String indexKey(IndexSchema idx) => idx.columns.join(',');
      final prevIdxMap = {for (final idx in prevTable.indexes) indexKey(idx): idx};
      final currIdxMap = {for (final idx in currTable.indexes) indexKey(idx): idx};

      // 追加インデックス
      for (final idx in currTable.indexes) {
        if (!prevIdxMap.containsKey(indexKey(idx))) {
          diffs.add(_SchemaDiff(
            type: _DiffType.addIndex,
            table: currTable,
            index: idx,
          ));
        }
      }

      // 削除インデックス
      for (final idx in prevTable.indexes) {
        if (!currIdxMap.containsKey(indexKey(idx))) {
          diffs.add(_SchemaDiff(
            type: _DiffType.dropIndex,
            table: currTable,
            index: idx,
          ));
        }
      }
    }

    return diffs;
  }

  /// 同じテーブルでDROP+ADDのペアを検出し、リネームかどうかユーザーに確認
  Future<List<_SchemaDiff>> _detectRenames(List<_SchemaDiff> diffs) async {
    final result = <_SchemaDiff>[];
    final toRemove = <_SchemaDiff>{};

    // テーブルごとにDROP/ADDカラムをグループ化
    final dropsByTable = <String, List<_SchemaDiff>>{};
    final addsByTable = <String, List<_SchemaDiff>>{};

    for (final diff in diffs) {
      if (diff.type == _DiffType.dropColumn) {
        dropsByTable.putIfAbsent(diff.table.name, () => []).add(diff);
      } else if (diff.type == _DiffType.addColumn) {
        addsByTable.putIfAbsent(diff.table.name, () => []).add(diff);
      }
    }

    // 各テーブルでDROP+ADDのペアを検出
    for (final tableName in dropsByTable.keys) {
      final drops = dropsByTable[tableName]!;
      final adds = addsByTable[tableName] ?? [];

      if (adds.isEmpty) continue;

      for (final dropDiff in drops) {
        if (toRemove.contains(dropDiff)) continue;

        for (final addDiff in adds) {
          if (toRemove.contains(addDiff)) continue;

          // リネームの可能性をユーザーに確認
          final oldName = dropDiff.column!.name;
          final newName = addDiff.column!.name;

          print('');
          stdout.write(
            '❓ Is column "$newName" in table "$tableName" renamed from "$oldName"? [y/N]: ',
          );

          final input = stdin.readLineSync()?.toLowerCase() ?? '';
          if (input == 'y' || input == 'yes') {
            // リネームとして記録
            result.add(_SchemaDiff(
              type: _DiffType.renameColumn,
              table: dropDiff.table,
              column: addDiff.column, // 新しいカラム
              oldColumn: dropDiff.column, // 古いカラム
            ));
            toRemove.add(dropDiff);
            toRemove.add(addDiff);
            break; // このドロップは処理済み
          }
        }
      }
    }

    // リネームにならなかったdiffを追加
    for (final diff in diffs) {
      if (!toRemove.contains(diff)) {
        result.add(diff);
      }
    }

    return result;
  }

  String _generateMigrationFile(List<_SchemaDiff> diffs) {
    final buffer = StringBuffer();
    buffer.writeln('-- Generated by aim db:generate');
    buffer.writeln('-- ${DateTime.now().toIso8601String()}');
    buffer.writeln();
    buffer.writeln('-- UP');
    buffer.write(_generateUpSql(diffs));
    buffer.writeln();
    buffer.writeln('-- DOWN');
    buffer.write(_generateDownSql(diffs));
    return buffer.toString();
  }

  String _generateUpSql(List<_SchemaDiff> diffs) {
    final buffer = StringBuffer();

    for (final diff in diffs) {
      final note = diff.note;
      if (note != null) buffer.writeln(note);
      switch (diff.type) {
        case _DiffType.createTable:
          buffer.writeln(_generateCreateTable(diff.table));
        case _DiffType.dropTable:
          buffer.writeln('DROP TABLE IF EXISTS ${diff.table.name};');
        case _DiffType.addColumn:
          buffer.writeln(
            'ALTER TABLE ${diff.table.name} ADD COLUMN ${_columnToSql(diff.column!)};',
          );
        case _DiffType.dropColumn:
          buffer.writeln(
            'ALTER TABLE ${diff.table.name} DROP COLUMN ${diff.column!.name};',
          );
        case _DiffType.addForeignKey:
          final fk = diff.foreignKey!;
          final constraintName = 'fk_${diff.table.name}_${fk.column}';
          var sql =
              'ALTER TABLE ${diff.table.name} ADD CONSTRAINT $constraintName '
              'FOREIGN KEY (${fk.column}) REFERENCES ${fk.referencesTable}(${fk.referencesColumn})';
          if (fk.onDelete != null) {
            sql += ' ON DELETE ${_onDeleteKeyword(fk.onDelete!)}';
          }
          if (fk.onUpdate != null) {
            sql += ' ON UPDATE ${_onUpdateKeyword(fk.onUpdate!)}';
          }
          buffer.writeln('$sql;');
        case _DiffType.dropForeignKey:
          final fk = diff.foreignKey!;
          final constraintName = 'fk_${diff.table.name}_${fk.column}';
          buffer.writeln(
            'ALTER TABLE ${diff.table.name} DROP CONSTRAINT $constraintName;',
          );
        case _DiffType.addIndex:
          final idx = diff.index!;
          final indexName = 'idx_${diff.table.name}_${idx.columns.join('_')}';
          final unique = idx.unique ? 'UNIQUE ' : '';
          buffer.writeln(
            'CREATE ${unique}INDEX $indexName ON ${diff.table.name} (${idx.columns.join(', ')});',
          );
        case _DiffType.dropIndex:
          final idx = diff.index!;
          final indexName = 'idx_${diff.table.name}_${idx.columns.join('_')}';
          buffer.writeln('DROP INDEX $indexName;');
        case _DiffType.alterColumnType:
          final col = diff.column!;
          buffer.writeln(
            'ALTER TABLE ${diff.table.name} ALTER COLUMN ${col.name} TYPE ${_columnTypeToSql(col)};',
          );
        case _DiffType.alterColumnSetNotNull:
          buffer.writeln(
            'ALTER TABLE ${diff.table.name} ALTER COLUMN ${diff.column!.name} SET NOT NULL;',
          );
        case _DiffType.alterColumnDropNotNull:
          buffer.writeln(
            'ALTER TABLE ${diff.table.name} ALTER COLUMN ${diff.column!.name} DROP NOT NULL;',
          );
        case _DiffType.alterColumnSetDefault:
          final col = diff.column!;
          if (col.defaultValue == _hasDefaultSentinel) {
            // The recorded schema says this column has a default but not
            // what it is, so there is no value to write. Putting the
            // marker into the statement would hand Postgres SQL it
            // rejects, which is worse than saying nothing can be done.
            buffer.writeln(
              '-- Cannot set the default for "${col.name}": the recorded '
              'schema says it has one, but not its value.',
            );
          } else {
            buffer.writeln(
              'ALTER TABLE ${diff.table.name} ALTER COLUMN ${col.name} '
              'SET DEFAULT ${col.defaultValue};',
            );
          }
        case _DiffType.alterColumnDropDefault:
          buffer.writeln(
            'ALTER TABLE ${diff.table.name} ALTER COLUMN ${diff.column!.name} DROP DEFAULT;',
          );
        case _DiffType.addUnique:
          final col = diff.column!;
          final constraintName = 'uq_${diff.table.name}_${col.name}';
          buffer.writeln(
            'ALTER TABLE ${diff.table.name} ADD CONSTRAINT $constraintName UNIQUE (${col.name});',
          );
        case _DiffType.dropUnique:
          final col = diff.column!;
          final constraintName = 'uq_${diff.table.name}_${col.name}';
          buffer.writeln(
            'ALTER TABLE ${diff.table.name} DROP CONSTRAINT $constraintName;',
          );
        case _DiffType.renameColumn:
          final oldName = diff.oldColumn!.name;
          final newName = diff.column!.name;
          buffer.writeln(
            'ALTER TABLE ${diff.table.name} RENAME COLUMN $oldName TO $newName;',
          );
      }
      buffer.writeln();
    }

    return buffer.toString();
  }

  /// The DOWN section: every diff inverted and run back through the UP
  /// generator, so both sections come from one set of SQL templates.
  String _generateDownSql(List<_SchemaDiff> diffs) =>
      _generateUpSql(_invertDiffs(diffs));

  /// カラム型のシグネチャ（型変更検出用）
  String _columnTypeSignature(ColumnSchema col) {
    if (col.type == 'varchar') {
      return col.varcharLength == null
          ? 'varchar'
          : 'varchar(${col.varcharLength})';
    }
    return col.type;
  }

  /// カラム型のSQL表現
  String _columnTypeToSql(ColumnSchema col) {
    switch (col.type) {
      case 'integer':
        return 'INTEGER';
      case 'serial':
        return 'SERIAL';
      case 'varchar':
        return col.varcharLength == null
            ? 'VARCHAR'
            : 'VARCHAR(${col.varcharLength})';
      case 'text':
        return 'TEXT';
      case 'timestamp':
        return 'TIMESTAMP';
      case 'uuid':
        return 'UUID';
      case 'jsonb':
        return 'JSONB';
      default:
        return 'TEXT';
    }
  }

  String _generateCreateTable(TableSchema table) {
    final buffer = StringBuffer();
    buffer.writeln('CREATE TABLE ${table.name} (');

    final columnDefs = <String>[];
    for (final col in table.columns) {
      columnDefs.add('  ${_columnToSql(col)}');
    }

    // 外部キー制約
    for (final fk in table.foreignKeys) {
      var fkDef =
          '  FOREIGN KEY (${fk.column}) REFERENCES ${fk.referencesTable}(${fk.referencesColumn})';
      if (fk.onDelete != null) {
        fkDef += ' ON DELETE ${_onDeleteKeyword(fk.onDelete!)}';
      }
      if (fk.onUpdate != null) {
        fkDef += ' ON UPDATE ${_onUpdateKeyword(fk.onUpdate!)}';
      }
      columnDefs.add(fkDef);
    }

    buffer.writeln(columnDefs.join(',\n'));
    buffer.write(');');

    // インデックス
    for (final idx in table.indexes) {
      buffer.writeln();
      buffer.write(
        'CREATE INDEX idx_${table.name}_${idx.columns.join('_')} '
        'ON ${table.name} (${idx.columns.join(', ')});',
      );
    }

    return buffer.toString();
  }

  String _columnToSql(ColumnSchema col) {
    final parts = <String>[col.name];

    switch (col.type) {
      case 'integer':
        parts.add('INTEGER');
      case 'serial':
        parts.add('SERIAL');
      case 'varchar':
        parts.add(
          col.varcharLength == null
              ? 'VARCHAR'
              : 'VARCHAR(${col.varcharLength})',
        );
      case 'text':
        parts.add('TEXT');
      case 'timestamp':
        parts.add('TIMESTAMP');
      case 'uuid':
        parts.add('UUID');
      case 'jsonb':
        parts.add('JSONB');
      default:
        parts.add('TEXT');
    }

    if (col.isPrimaryKey) parts.add('PRIMARY KEY');
    if (col.isUnique) parts.add('UNIQUE');
    if (!col.isNullable && !col.isPrimaryKey) parts.add('NOT NULL');
    if (col.defaultValue != null && col.defaultValue != _hasDefaultSentinel) {
      parts.add('DEFAULT ${col.defaultValue}');
    }

    return parts.join(' ');
  }
}

// --- データクラス ---

class Schema {
  final List<TableSchema> tables;

  Schema({required this.tables});

  factory Schema.fromJson(Map<String, dynamic> json) {
    return Schema(
      tables:
          (json['tables'] as List).map((t) => TableSchema.fromJson(t)).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'tables': tables.map((t) => t.toJson()).toList(),
      };
}

class TableSchema {
  final String name;
  final List<ColumnSchema> columns;
  final List<IndexSchema> indexes;
  final List<ForeignKeySchema> foreignKeys;

  TableSchema({
    required this.name,
    required this.columns,
    this.indexes = const [],
    this.foreignKeys = const [],
  });

  factory TableSchema.fromJson(Map<String, dynamic> json) {
    return TableSchema(
      name: json['name'],
      columns:
          (json['columns'] as List).map((c) => ColumnSchema.fromJson(c)).toList(),
      indexes: (json['indexes'] as List?)
              ?.map((i) => IndexSchema.fromJson(i))
              .toList() ??
          [],
      foreignKeys: (json['foreignKeys'] as List?)
              ?.map((f) => ForeignKeySchema.fromJson(f))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'columns': columns.map((c) => c.toJson()).toList(),
        'indexes': indexes.map((i) => i.toJson()).toList(),
        'foreignKeys': foreignKeys.map((f) => f.toJson()).toList(),
      };
}

class ColumnSchema {
  final String name;
  final String type;
  final bool isPrimaryKey;
  final bool isUnique;
  final bool isNullable;
  final int? varcharLength;
  final String? defaultValue; // SQL表現の文字列

  ColumnSchema({
    required this.name,
    required this.type,
    this.isPrimaryKey = false,
    this.isUnique = false,
    this.isNullable = false,
    this.varcharLength,
    this.defaultValue,
  });

  factory ColumnSchema.fromJson(Map<String, dynamic> json) {
    return ColumnSchema(
      name: json['name'],
      type: json['type'],
      isPrimaryKey: json['isPrimaryKey'] ?? false,
      isUnique: json['isUnique'] ?? false,
      isNullable: json['isNullable'] ?? false,
      varcharLength: json['varcharLength'],
      defaultValue: json['defaultValue'],
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        'isPrimaryKey': isPrimaryKey,
        'isUnique': isUnique,
        'isNullable': isNullable,
        if (varcharLength != null) 'varcharLength': varcharLength,
        if (defaultValue != null) 'defaultValue': defaultValue,
      };
}

class IndexSchema {
  final List<String> columns;
  final bool unique;

  IndexSchema({required this.columns, this.unique = false});

  factory IndexSchema.fromJson(Map<String, dynamic> json) {
    return IndexSchema(
      columns: List<String>.from(json['columns']),
      unique: json['unique'] ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'columns': columns,
        'unique': unique,
      };
}

class ForeignKeySchema {
  final String column;
  final String referencesTable;
  final String referencesColumn;
  final String? onDelete;
  final String? onUpdate;

  ForeignKeySchema({
    required this.column,
    required this.referencesTable,
    required this.referencesColumn,
    this.onDelete,
    this.onUpdate,
  });

  factory ForeignKeySchema.fromJson(Map<String, dynamic> json) {
    return ForeignKeySchema(
      column: json['column'],
      referencesTable: json['referencesTable'],
      referencesColumn: json['referencesColumn'],
      onDelete: json['onDelete'],
      onUpdate: json['onUpdate'],
    );
  }

  Map<String, dynamic> toJson() => {
        'column': column,
        'referencesTable': referencesTable,
        'referencesColumn': referencesColumn,
        if (onDelete != null) 'onDelete': onDelete,
        if (onUpdate != null) 'onUpdate': onUpdate,
      };
}

class _ColumnAnalysisResult {
  final ColumnSchema column;
  final bool isIndexed;
  final ForeignKeySchema? foreignKey;

  _ColumnAnalysisResult({
    required this.column,
    this.isIndexed = false,
    this.foreignKey,
  });
}

enum _DiffType {
  createTable,
  dropTable,
  addColumn,
  dropColumn,
  addForeignKey,
  dropForeignKey,
  addIndex,
  dropIndex,
  alterColumnType,
  alterColumnSetNotNull,
  alterColumnDropNotNull,
  alterColumnSetDefault,
  alterColumnDropDefault,
  addUnique,
  dropUnique,
  renameColumn,
}

class _SchemaDiff {
  final _DiffType type;
  final TableSchema table;
  final ColumnSchema? column; // ADD/DROP/ALTER COLUMN 用
  final ColumnSchema? oldColumn; // ALTER COLUMN 用（変更前）
  final ForeignKeySchema? foreignKey; // ADD/DROP FOREIGN KEY 用
  final IndexSchema? index; // ADD/DROP INDEX 用

  /// Comment lines written immediately above this diff's statement.
  ///
  /// Set when inverting a diff for the DOWN section and the statement
  /// cannot put everything back, so the file says what will not return.
  /// Diffs coming from the schema comparison never carry one.
  final String? note;

  _SchemaDiff({
    required this.type,
    required this.table,
    this.column,
    this.oldColumn,
    this.foreignKey,
    this.index,
    this.note,
  });
}

/// Stored in [ColumnSchema.defaultValue] when the schema declares a default
/// whose Dart expression is not a literal. The analyzer can record that the
/// column has a default, but not a value that could be written into SQL.
const _hasDefaultSentinel = '__HAS_DEFAULT__';

/// Written above a statement that brings a dropped table back. The
/// structure returns; the rows do not.
const _tableDataLostNote =
    '-- Restores the table structure only. Rows removed by the UP section\n'
    '-- are not recovered.';

/// Written above a statement that brings a dropped column back.
const _columnDataLostNote =
    '-- Restores the column only. Values removed by the UP section are not\n'
    '-- recovered.';

/// Added below [_columnDataLostNote] when the column cannot be added back
/// to a table that still has rows.
const _notNullAddNote =
    '-- This statement fails if the table already has rows: the column is\n'
    '-- NOT NULL with no default.';

/// Whether adding [col] to a table that already has rows would fail.
///
/// Postgres has to put something in the new column for every existing row.
/// It can do that from a default; with no default and no NULLs allowed
/// there is nothing it can write. A column whose recorded default is the
/// marker counts as having none, because no DEFAULT clause is rendered for
/// it.
bool _needsValueForExistingRows(ColumnSchema col) =>
    !col.isNullable &&
    (col.defaultValue == null || col.defaultValue == _hasDefaultSentinel);

/// Every diff in [diffs] replaced by the change that undoes it.
///
/// The DOWN section is generated by handing this list to [_generateUpSql],
/// so UP and DOWN share one set of SQL templates: a statement added to the
/// generator cannot be forgotten on the DOWN side.
///
/// This works because every diff that removes something carries the
/// removed object itself — the previous schema's table, column, foreign
/// key or index — so the restoring statement can be written in full. What
/// does not come back is the data, so those inversions carry a note that
/// says as much.
List<_SchemaDiff> _invertDiffs(List<_SchemaDiff> diffs) =>
    _orderForExecution([for (final diff in diffs) _invertDiff(diff)]);

/// The change that undoes [diff].
_SchemaDiff _invertDiff(_SchemaDiff diff) {
  switch (diff.type) {
    case _DiffType.createTable:
      return _SchemaDiff(type: _DiffType.dropTable, table: diff.table);
    case _DiffType.dropTable:
      return _SchemaDiff(
        type: _DiffType.createTable,
        table: diff.table,
        note: _tableDataLostNote,
      );
    case _DiffType.addColumn:
      return _SchemaDiff(
        type: _DiffType.dropColumn,
        table: diff.table,
        column: diff.column,
      );
    case _DiffType.dropColumn:
      final col = diff.column!;
      return _SchemaDiff(
        type: _DiffType.addColumn,
        table: diff.table,
        column: col,
        note: _needsValueForExistingRows(col)
            ? '$_columnDataLostNote\n$_notNullAddNote'
            : _columnDataLostNote,
      );
    case _DiffType.addForeignKey:
      return _SchemaDiff(
        type: _DiffType.dropForeignKey,
        table: diff.table,
        foreignKey: diff.foreignKey,
      );
    case _DiffType.dropForeignKey:
      return _SchemaDiff(
        type: _DiffType.addForeignKey,
        table: diff.table,
        foreignKey: diff.foreignKey,
      );
    case _DiffType.addIndex:
      return _SchemaDiff(
        type: _DiffType.dropIndex,
        table: diff.table,
        index: diff.index,
      );
    case _DiffType.dropIndex:
      return _SchemaDiff(
        type: _DiffType.addIndex,
        table: diff.table,
        index: diff.index,
      );
    case _DiffType.addUnique:
      return _SchemaDiff(
        type: _DiffType.dropUnique,
        table: diff.table,
        column: diff.column,
      );
    case _DiffType.dropUnique:
      return _SchemaDiff(
        type: _DiffType.addUnique,
        table: diff.table,
        column: diff.column,
      );
    case _DiffType.alterColumnType:
      return _SchemaDiff(
        type: _DiffType.alterColumnType,
        table: diff.table,
        column: diff.oldColumn,
        oldColumn: diff.column,
      );
    case _DiffType.alterColumnSetNotNull:
      return _SchemaDiff(
        type: _DiffType.alterColumnDropNotNull,
        table: diff.table,
        column: diff.column,
      );
    case _DiffType.alterColumnDropNotNull:
      return _SchemaDiff(
        type: _DiffType.alterColumnSetNotNull,
        table: diff.table,
        column: diff.column,
      );
    case _DiffType.alterColumnSetDefault:
      // The schema comparison records the previous column on every default
      // change, so the value to go back to is known. Where there was no
      // default before, going back means dropping this one.
      final old = diff.oldColumn!;
      if (old.defaultValue == null) {
        return _SchemaDiff(
          type: _DiffType.alterColumnDropDefault,
          table: diff.table,
          column: diff.column,
        );
      }
      return _SchemaDiff(
        type: _DiffType.alterColumnSetDefault,
        table: diff.table,
        column: old,
        oldColumn: diff.column,
      );
    case _DiffType.alterColumnDropDefault:
      // A default was dropped, so the previous column had one: putting the
      // old column in `column` is what makes the generator write its value.
      return _SchemaDiff(
        type: _DiffType.alterColumnSetDefault,
        table: diff.table,
        column: diff.oldColumn!,
        oldColumn: diff.column,
      );
    case _DiffType.renameColumn:
      return _SchemaDiff(
        type: _DiffType.renameColumn,
        table: diff.table,
        column: diff.oldColumn,
        oldColumn: diff.column,
      );
  }
}

/// When [type]'s statement has to run relative to the others.
///
/// Statements go out from the lowest phase up. Things that depend on
/// something else come off first and go back on last: an index or
/// constraint before the column it sits on, a column before its table.
/// Read the table downwards and every statement finds what it needs
/// already there.
int _executionPhase(_DiffType type) => switch (type) {
  _DiffType.dropIndex || _DiffType.dropForeignKey || _DiffType.dropUnique => 0,
  _DiffType.dropColumn => 1,
  _DiffType.dropTable => 2,
  _DiffType.createTable => 3,
  _DiffType.addColumn => 4,
  _DiffType.alterColumnType ||
  _DiffType.alterColumnSetNotNull ||
  _DiffType.alterColumnDropNotNull ||
  _DiffType.alterColumnSetDefault ||
  _DiffType.alterColumnDropDefault ||
  _DiffType.renameColumn => 5,
  _DiffType.addUnique || _DiffType.addForeignKey || _DiffType.addIndex => 6,
};

/// [diffs] ordered so every statement can run.
///
/// Sorted by [_executionPhase], keeping the input order inside a phase,
/// and with the CREATE TABLE phase ordered by foreign key reference.
List<_SchemaDiff> _orderForExecution(List<_SchemaDiff> diffs) {
  final byPhase = <int, List<_SchemaDiff>>{};
  for (final diff in diffs) {
    (byPhase[_executionPhase(diff.type)] ??= []).add(diff);
  }

  final createPhase = _executionPhase(_DiffType.createTable);
  final result = <_SchemaDiff>[];
  for (final phase in byPhase.keys.toList()..sort()) {
    final group = byPhase[phase]!;
    result.addAll(
      phase == createPhase ? _orderTablesByReference(group) : group,
    );
  }
  return result;
}

/// [creates] — all CREATE TABLE diffs — ordered so a table comes after the
/// tables its foreign keys point at.
///
/// CREATE TABLE writes its foreign keys inline, so the referenced table
/// has to exist already. References to tables outside [creates] need no
/// ordering: those tables are not being created here, so they are already
/// there. A table referencing itself is left alone. Tables in a reference
/// cycle keep their input order — Postgres rejects that schema either way,
/// and choosing an order would not help.
List<_SchemaDiff> _orderTablesByReference(List<_SchemaDiff> creates) {
  final byName = {for (final diff in creates) diff.table.name: diff};
  final ordered = <_SchemaDiff>[];
  final placed = <String>{};
  final visiting = <String>{};

  void place(_SchemaDiff diff) {
    final name = diff.table.name;
    if (placed.contains(name) || visiting.contains(name)) return;
    visiting.add(name);
    for (final fk in diff.table.foreignKeys) {
      if (fk.referencesTable == name) continue;
      final referenced = byName[fk.referencesTable];
      if (referenced != null) place(referenced);
    }
    visiting.remove(name);
    placed.add(name);
    ordered.add(diff);
  }

  for (final diff in creates) {
    place(diff);
  }
  return ordered;
}

/// Convert string to snake_case for migration file names
String _toSnakeCase(String input) {
  // スペースやハイフンをアンダースコアに変換
  var result = input.replaceAll(RegExp(r'[\s\-]+'), '_');
  // キャメルケースをスネークケースに変換
  result = result.replaceAllMapped(
    RegExp(r'[A-Z]'),
    (match) => '_${match.group(0)!.toLowerCase()}',
  );
  // 先頭のアンダースコアを削除
  result = result.replaceAll(RegExp(r'^_+'), '');
  // 連続するアンダースコアを1つに
  result = result.replaceAll(RegExp(r'_+'), '_');
  return result.toLowerCase();
}

/// Extract aim.database.schema from pubspec.yaml content
String? _extractAimSchema(String content) {
  final yaml = loadYaml(content);
  if (yaml is! YamlMap) return null;

  final aim = yaml['aim'];
  if (aim is! YamlMap) return null;

  final database = aim['database'];
  if (database is! YamlMap) return null;

  return database['schema'] as String?;
}
