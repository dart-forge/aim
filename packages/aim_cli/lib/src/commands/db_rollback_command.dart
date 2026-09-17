import 'dart:io';

import 'package:aim_cli/src/migration/down_statements.dart';
import 'package:aim_postgres/aim_postgres.dart';
import 'package:args/command_runner.dart';
import 'package:yaml/yaml.dart';

class DbRollbackCommand extends Command<void> {
  @override
  String get name => 'db:rollback';

  @override
  String get description => 'Rollback the last applied migration(s)';

  DbRollbackCommand() {
    argParser.addOption(
      'step',
      abbr: 's',
      help: 'Number of migrations to rollback (default: 1)',
      defaultsTo: '1',
    );
    argParser.addOption(
      'target',
      abbr: 't',
      help: 'Rollback to this target migration (exclusive)',
    );
  }

  @override
  Future<void> run() async {
    // 1. DB接続情報を取得
    final dbUrl = await _getDatabaseUrl();
    if (dbUrl == null) {
      print('Error: Database URL not found');
      print('Set aim.database.url in pubspec.yaml');
      exit(1);
    }

    // 2. マイグレーションファイルを取得
    final migrationsDir = Directory('db/migrations');
    if (!await migrationsDir.exists()) {
      print('No migrations directory found');
      return;
    }

    final migrationFiles = await migrationsDir
        .list()
        .where((f) => f is File && f.path.endsWith('.sql'))
        .cast<File>()
        .toList();

    if (migrationFiles.isEmpty) {
      print('No migration files found');
      return;
    }

    // ファイル名をキーにしたマップを作成
    final fileMap = {
      for (final f in migrationFiles) _migrationName(f): f,
    };

    // 3. DB接続
    print('🔌 Connecting to database...');
    final db = await PostgresDatabase.connect(dbUrl);

    try {
      // 4. 適用済みマイグレーションを取得（新しい順）
      final applied = await _getAppliedMigrations(db);

      if (applied.isEmpty) {
        print('✅ No migrations to rollback');
        return;
      }

      // 5. ロールバック対象を決定
      final target = argResults?['target'] as String?;
      final step = int.tryParse(argResults?['step'] as String? ?? '1') ?? 1;

      final toRollback = <String>[];

      if (target != null) {
        // --target指定: 指定されたマイグレーションの直後まで戻す
        for (final name in applied) {
          if (name == target || name.startsWith(target)) {
            break;
          }
          toRollback.add(name);
        }
      } else {
        // --step指定: 指定された数だけ戻す
        toRollback.addAll(applied.take(step));
      }

      if (toRollback.isEmpty) {
        print('✅ No migrations to rollback');
        return;
      }

      print('🔄 Rolling back ${toRollback.length} migration(s)');
      print('');

      // 6. ロールバックを実行
      for (final name in toRollback) {
        final file = fileMap[name];
        if (file == null) {
          print('  ⚠️  Migration file not found: $name');
          print('  Skipping...');
          continue;
        }

        final content = await file.readAsString();
        final sections = _parseMigrationSections(content);
        final statements = executableStatements(sections.down ?? '');

        print('  Rolling back: $name');

        if (statements.isEmpty) {
          if (sections.down == null || sections.down!.trim().isEmpty) {
            print('  ⚠️  No DOWN section found');
          } else {
            // A DOWN section that is only comments — migrations generated
            // before the generator could write these statements say in a
            // comment that the old schema was unavailable. Running it
            // would change nothing while reporting success.
            print('  ⚠️  The DOWN section has no statements, only comments');
          }
          print('  Cannot rollback this migration automatically.');
          print('');
          stdout.write('  Continue anyway (remove from history only)? [y/N]: ');
          final input = stdin.readLineSync()?.toLowerCase() ?? '';
          if (input != 'y' && input != 'yes') {
            print('  Rollback stopped.');
            exit(1);
          }
          await _removeMigration(db, name);
        } else {
          try {
            // One transaction per migration: the statements and the
            // history row go together, so a failure half way through
            // leaves neither a half-rolled-back schema nor a history that
            // disagrees with it. Postgres rolls DDL back too.
            await db.transaction((tx) async {
              for (final stmt in statements) {
                await tx.execute(stmt);
              }
              await _removeMigration(tx, name);
            });
          } catch (e) {
            print('  ❌ Failed: $name');
            print('  Error: $e');
            print('');
            print('Rollback stopped. Please fix the error and retry.');
            exit(1);
          }
        }

        print('  ✅ Rolled back: $name');
      }

      print('');
      print('✅ Rollback completed');
    } finally {
      await db.close();
    }
  }

  Future<String?> _getDatabaseUrl() async {
    final pubspecFile = File('pubspec.yaml');
    if (!await pubspecFile.exists()) return null;

    final content = await pubspecFile.readAsString();
    final yaml = loadYaml(content);

    if (yaml is! YamlMap) return null;
    final aim = yaml['aim'];
    if (aim is! YamlMap) return null;
    final database = aim['database'];
    if (database is! YamlMap) return null;

    return database['url'] as String?;
  }

  String _fileName(File file) {
    return file.path.split('/').last;
  }

  String _migrationName(File file) {
    final name = _fileName(file);
    return name.endsWith('.sql') ? name.substring(0, name.length - 4) : name;
  }

  /// 適用済みマイグレーションを取得（新しい順）
  Future<List<String>> _getAppliedMigrations(PostgresDatabase db) async {
    // テーブルが存在するか確認
    final tableExists = await db.query('''
      SELECT EXISTS (
        SELECT FROM information_schema.tables
        WHERE table_name = '_aim_migrations'
      ) as exists
    ''');
    if (tableExists.isEmpty) {
      return [];
    }
    // PostgreSQLのbool値はtrue/falseまたは't'/'f'で返る可能性がある
    final existsValue = tableExists.first['exists'];
    final exists = existsValue == true || existsValue == 't';
    if (!exists) {
      return [];
    }

    final result = await db.query(
      'SELECT name FROM _aim_migrations ORDER BY name DESC',
    );
    return result.map((row) => row['name'] as String).toList();
  }

  Future<void> _removeMigration(PostgresQueryable q, String name) async {
    await q.execute(
      'DELETE FROM _aim_migrations WHERE name = :name',
      params: {'name': name},
    );
  }

  /// マイグレーションファイルをUP/DOWNセクションに分離
  _MigrationSections _parseMigrationSections(String content) {
    final upMatch =
        RegExp(r'^--\s*UP\s*$', multiLine: true).firstMatch(content);
    final downMatch =
        RegExp(r'^--\s*DOWN\s*$', multiLine: true).firstMatch(content);

    if (upMatch == null) {
      return _MigrationSections(up: content, down: null);
    }

    String upSql;
    String? downSql;

    if (downMatch != null && downMatch.start > upMatch.end) {
      upSql = content.substring(upMatch.end, downMatch.start).trim();
      downSql = content.substring(downMatch.end).trim();
    } else {
      upSql = content.substring(upMatch.end).trim();
      downSql = null;
    }

    return _MigrationSections(up: upSql, down: downSql);
  }
}

class _MigrationSections {
  final String up;
  final String? down;

  _MigrationSections({required this.up, this.down});
}
