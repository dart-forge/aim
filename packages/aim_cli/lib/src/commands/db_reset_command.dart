import 'dart:convert';
import 'dart:io';

import 'package:aim_cli/src/config/aim_config.dart';
import 'package:aim_postgres/aim_postgres.dart';
import 'package:args/command_runner.dart';
import 'package:crypto/crypto.dart';

class DbResetCommand extends Command<void> {
  @override
  String get name => 'db:reset';

  @override
  String get description =>
      'Drop database, recreate it, and apply all migrations';

  DbResetCommand() {
    argParser.addFlag(
      'force',
      abbr: 'f',
      help: 'Skip confirmation prompt',
      negatable: false,
    );
  }

  @override
  Future<void> run() async {
    // 1. Get database connection info
    final dbUrl = (await AimConfig.loadOrDefault()).database.url;
    if (dbUrl == null) {
      print('Error: Database URL not found');
      print('Set aim.database.url in pubspec.yaml');
      exit(1);
    }

    // 2. Extract database name from URL
    final parsedUrl = _parsePostgresUrl(dbUrl);
    if (parsedUrl == null) {
      print('Error: Invalid database URL format');
      exit(1);
    }

    final dbName = parsedUrl.database;

    // 3. Confirmation prompt
    final force = argResults?['force'] as bool? ?? false;
    if (!force) {
      print('⚠️  This will drop and recreate database "$dbName"');
      print('   All data will be lost!');
      print('');
      stdout.write('Are you sure? [y/N]: ');
      final input = stdin.readLineSync()?.toLowerCase() ?? '';
      if (input != 'y' && input != 'yes') {
        print('Aborted.');
        exit(0);
      }
      print('');
    }

    // 4. Connect to postgres database (for admin operations)
    print('🔌 Connecting to postgres database...');
    final adminUrl = parsedUrl.toAdminUrl();
    final adminDb = await PostgresDatabase.connect(adminUrl);

    try {
      // 5. Terminate existing connections and drop database
      print('🗑️  Dropping database "$dbName"...');

      // Terminate existing connections
      await adminDb.execute('''
        SELECT pg_terminate_backend(pg_stat_activity.pid)
        FROM pg_stat_activity
        WHERE pg_stat_activity.datname = :dbName
          AND pid <> pg_backend_pid()
      ''', params: {'dbName': dbName});

      // Drop database if exists
      await adminDb.execute('DROP DATABASE IF EXISTS "$dbName"');

      // 6. Recreate database
      print('🔨 Creating database "$dbName"...');
      await adminDb.execute('CREATE DATABASE "$dbName"');
    } finally {
      await adminDb.close();
    }

    // 7. Connect to target database and apply migrations
    print('🔌 Connecting to database "$dbName"...');
    final db = await PostgresDatabase.connect(dbUrl);

    try {
      await _applyAllMigrations(db);
    } finally {
      await db.close();
    }

    print('');
    print('✅ Database reset complete');
  }

  Future<void> _applyAllMigrations(PostgresDatabase db) async {
    // Get migration files
    final migrationsDir = Directory('db/migrations');
    if (!await migrationsDir.exists()) {
      print('📦 No migrations directory found');
      return;
    }

    final migrationFiles = await migrationsDir
        .list()
        .where((f) => f is File && f.path.endsWith('.sql'))
        .cast<File>()
        .toList();

    if (migrationFiles.isEmpty) {
      print('📦 No migration files found');
      return;
    }

    // Sort by filename
    migrationFiles.sort((a, b) => _fileName(a).compareTo(_fileName(b)));

    // Create migrations table
    await _ensureMigrationsTable(db);

    print('📦 Applying ${migrationFiles.length} migration(s)...');
    print('');

    // Apply migrations
    for (final file in migrationFiles) {
      final name = _migrationName(file);
      final content = await file.readAsString();
      final checksum = _calculateChecksum(content);

      // Parse UP/DOWN sections
      final sections = _parseMigrationSections(content);
      final upSql = sections.up;

      print('  Applying: $name');

      try {
        // Execute UP SQL
        final statements = _splitStatements(upSql);
        for (final stmt in statements) {
          if (stmt.trim().isNotEmpty) {
            await db.execute(stmt);
          }
        }
        await _recordMigration(db, name, checksum);
        print('  ✅ Applied: $name');
      } catch (e) {
        print('  ❌ Failed: $name');
        print('  Error: $e');
        print('');
        print('Migration stopped. Please fix the error and retry.');
        exit(1);
      }
    }

    print('');
    print('✅ All migrations applied successfully');
  }

  _ParsedPostgresUrl? _parsePostgresUrl(String url) {
    // postgres://user:password@host:port/database
    // postgresql://user:password@host:port/database
    final uri = Uri.tryParse(url);
    if (uri == null) return null;

    if (uri.scheme != 'postgres' && uri.scheme != 'postgresql') {
      return null;
    }

    final database = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    if (database == null || database.isEmpty) return null;

    return _ParsedPostgresUrl(
      scheme: uri.scheme,
      username: uri.userInfo.split(':').first,
      password:
          uri.userInfo.contains(':') ? uri.userInfo.split(':').skip(1).join(':') : null,
      host: uri.host,
      port: uri.port != 0 ? uri.port : 5432,
      database: database,
    );
  }

  String _fileName(File file) {
    return file.path.split('/').last;
  }

  String _migrationName(File file) {
    final name = _fileName(file);
    return name.endsWith('.sql') ? name.substring(0, name.length - 4) : name;
  }

  String _calculateChecksum(String content) {
    return md5.convert(utf8.encode(content)).toString();
  }

  List<String> _splitStatements(String sql) {
    final statements = <String>[];
    final buffer = StringBuffer();
    bool inSingleLineComment = false;
    bool inMultiLineComment = false;

    for (var i = 0; i < sql.length; i++) {
      final char = sql[i];
      final nextChar = i + 1 < sql.length ? sql[i + 1] : '';

      if (!inMultiLineComment && char == '-' && nextChar == '-') {
        inSingleLineComment = true;
        buffer.write(char);
        continue;
      }

      if (inSingleLineComment && char == '\n') {
        inSingleLineComment = false;
        buffer.write(char);
        continue;
      }

      if (!inSingleLineComment && char == '/' && nextChar == '*') {
        inMultiLineComment = true;
        buffer.write(char);
        continue;
      }

      if (inMultiLineComment && char == '*' && nextChar == '/') {
        inMultiLineComment = false;
        buffer.write(char);
        continue;
      }

      if (char == ';' && !inSingleLineComment && !inMultiLineComment) {
        final stmt = buffer.toString().trim();
        if (stmt.isNotEmpty) {
          statements.add(stmt);
        }
        buffer.clear();
        continue;
      }

      buffer.write(char);
    }

    final lastStmt = buffer.toString().trim();
    if (lastStmt.isNotEmpty) {
      statements.add(lastStmt);
    }

    return statements;
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

  Future<void> _recordMigration(
    PostgresDatabase db,
    String name,
    String checksum,
  ) async {
    await db.execute(
      'INSERT INTO _aim_migrations (name, checksum) VALUES (:name, :checksum)',
      params: {'name': name, 'checksum': checksum},
    );
  }

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

class _ParsedPostgresUrl {
  final String scheme;
  final String username;
  final String? password;
  final String host;
  final int port;
  final String database;

  _ParsedPostgresUrl({
    required this.scheme,
    required this.username,
    this.password,
    required this.host,
    required this.port,
    required this.database,
  });

  /// Generate connection URL for postgres database (for admin operations)
  String toAdminUrl() {
    final userInfo = password != null ? '$username:$password' : username;
    return '$scheme://$userInfo@$host:$port/postgres';
  }
}

class _MigrationSections {
  final String up;
  final String? down;

  _MigrationSections({required this.up, this.down});
}