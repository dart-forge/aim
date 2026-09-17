import 'dart:convert';
import 'dart:io';

import 'package:aim_cli/src/migration/down_statements.dart';
import 'package:aim_postgres/aim_postgres.dart';
import 'package:args/command_runner.dart';
import 'package:crypto/crypto.dart';
import 'package:yaml/yaml.dart';

class DbMigrateCommand extends Command<void> {
  @override
  String get name => 'db:migrate';

  @override
  String get description => 'Apply pending migrations to the database';

  DbMigrateCommand() {
    argParser.addOption(
      'target',
      abbr: 't',
      help: 'Apply migrations up to this target (e.g., 20260120094025_add_users)',
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

    // ファイル名でソート
    migrationFiles.sort((a, b) => _fileName(a).compareTo(_fileName(b)));

    // 3. DB接続
    print('🔌 Connecting to database...');
    final db = await PostgresDatabase.connect(dbUrl);

    try {
      // 4. マイグレーションテーブルを作成（なければ）
      await _ensureMigrationsTable(db);

      // 5. 適用済みマイグレーションを取得
      final applied = await _getAppliedMigrations(db);

      // 6. 未適用のマイグレーションをフィルタ
      final target = argResults?['target'] as String?;
      final pending = <File>[];

      for (final file in migrationFiles) {
        final name = _migrationName(file);
        if (applied.contains(name)) continue;

        pending.add(file);

        // --target が指定されていて、そこに到達したら終了
        if (target != null && name.startsWith(target)) {
          break;
        }
      }

      if (pending.isEmpty) {
        print('✅ No pending migrations');
        return;
      }

      print('📦 Found ${pending.length} pending migration(s)');
      print('');

      // 7. マイグレーションを適用
      for (final file in pending) {
        final name = _migrationName(file);
        final content = await file.readAsString();
        final checksum = _calculateChecksum(content);

        // UP/DOWNセクションを分離
        final sections = _parseMigrationSections(content);
        final statements = executableStatements(sections.up);

        print('  Applying: $name');

        if (statements.isEmpty) {
          // Nothing the server would run. A generated migration ends up
          // like this when a change could not be expressed in SQL — a
          // default whose value the schema does not record, for instance —
          // and recording it as applied would leave the schema snapshot
          // claiming something the database does not have.
          print('  ⚠️  This migration has no statements to run.');
          print('  It was generated for a change that could not be written');
          print('  as SQL. Edit db/migrations/$name.sql and run again.');
          print('');
          print('Migration stopped.');
          exit(1);
        }

        final runOutsideTransaction = runsOutsideTransaction(content);

        try {
          if (runOutsideTransaction) {
            print('  Running outside a transaction (the file asks for it).');
            for (final stmt in statements) {
              await db.execute(stmt);
            }
            await _recordMigration(db, name, checksum);
          } else {
            // One transaction per migration: the statements and the history
            // row go together, so a failure part way through leaves the
            // database as it was. Postgres rolls DDL back too, which is why
            // there is no hand-written undo here — there is nothing to undo.
            await db.transaction((tx) async {
              for (final stmt in statements) {
                await tx.execute(stmt);
              }
              await _recordMigration(tx, name, checksum);
            });
          }
          print('  ✅ Applied: $name');
        } catch (e) {
          print('  ❌ Failed: $name');
          print('  Error: $e');
          print('');
          if (runOutsideTransaction) {
            print('  This migration ran without a transaction, so the');
            print('  statements before the failure are still applied.');
          } else if (e.toString().contains(
            'cannot run inside a transaction block',
          )) {
            print('  This statement has to run on its own. Put this line in');
            print('  the migration file to apply it without a transaction:');
            print('');
            print('    -- aim: no-transaction');
            print('');
            print('  Nothing from this migration was applied.');
          } else {
            print('  Nothing from this migration was applied.');
          }
          print('');
          print('Migration stopped. Please fix the error and retry.');
          exit(1);
        }
      }

      print('');
      print('✅ All migrations applied successfully');
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
    // 拡張子を除いたファイル名
    final name = _fileName(file);
    return name.endsWith('.sql') ? name.substring(0, name.length - 4) : name;
  }

  String _calculateChecksum(String content) {
    return md5.convert(utf8.encode(content)).toString();
  }

  Future<void> _ensureMigrationsTable(PostgresDatabase db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS _aim_migrations (
        id SERIAL PRIMARY KEY,
        name VARCHAR(255) NOT NULL UNIQUE,
        checksum VARCHAR(32) NOT NULL,
        applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');
  }

  Future<Set<String>> _getAppliedMigrations(PostgresDatabase db) async {
    final result = await db.query(
      'SELECT name FROM _aim_migrations ORDER BY name',
    );
    return result.map((row) => row['name'] as String).toSet();
  }

  Future<void> _recordMigration(
    PostgresQueryable q,
    String name,
    String checksum,
  ) async {
    await q.execute(
      'INSERT INTO _aim_migrations (name, checksum) VALUES (:name, :checksum)',
      params: {'name': name, 'checksum': checksum},
    );
  }

  /// マイグレーションファイルをUP/DOWNセクションに分離
  _MigrationSections _parseMigrationSections(String content) {
    // -- UP と -- DOWN のマーカーを探す
    final upMatch = RegExp(r'^--\s*UP\s*$', multiLine: true).firstMatch(content);
    final downMatch =
        RegExp(r'^--\s*DOWN\s*$', multiLine: true).firstMatch(content);

    if (upMatch == null) {
      // UPセクションがない場合、全体をUPとして扱う（後方互換性）
      return _MigrationSections(up: content, down: null);
    }

    String upSql;
    String? downSql;

    if (downMatch != null && downMatch.start > upMatch.end) {
      // UPとDOWN両方ある場合
      upSql = content.substring(upMatch.end, downMatch.start).trim();
      downSql = content.substring(downMatch.end).trim();
    } else {
      // UPのみの場合
      upSql = content.substring(upMatch.end).trim();
      downSql = null;
    }

    return _MigrationSections(up: upSql, down: downSql);
  }
}

/// マイグレーションのUP/DOWNセクション
class _MigrationSections {
  final String up;
  final String? down;

  _MigrationSections({required this.up, this.down});
}
