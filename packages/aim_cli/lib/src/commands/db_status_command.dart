import 'dart:io';

import 'package:aim_cli/src/config/aim_config.dart';
import 'package:aim_postgres/aim_postgres.dart';
import 'package:args/command_runner.dart';

class DbStatusCommand extends Command<void> {
  @override
  String get name => 'db:status';

  @override
  String get description => 'Show migration status';

  @override
  Future<void> run() async {
    // 1. DB接続情報を取得
    final dbUrl = (await AimConfig.loadOrDefault()).database.url;
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
    final db = await PostgresDatabase.connect(dbUrl);

    try {
      // 4. 適用済みマイグレーションを取得
      final applied = await _getAppliedMigrations(db);

      // 5. ステータス表示
      print('');
      print('Migration Status:');
      print('');

      int appliedCount = 0;
      int pendingCount = 0;

      for (final file in migrationFiles) {
        final name = _migrationName(file);
        final info = applied[name];

        if (info != null) {
          appliedCount++;
          print('  ✅ $name');
          print('     Applied: ${_formatDateTime(info.appliedAt)}');
        } else {
          pendingCount++;
          print('  ⏳ $name');
          print('     Status: Pending');
        }
      }

      print('');
      print('─' * 40);
      print('Applied: $appliedCount');
      print('Pending: $pendingCount');
      print('Total:   ${appliedCount + pendingCount}');
    } finally {
      await db.close();
    }
  }

  String _fileName(File file) {
    return file.path.split('/').last;
  }

  String _migrationName(File file) {
    final name = _fileName(file);
    return name.endsWith('.sql') ? name.substring(0, name.length - 4) : name;
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} '
        '${_pad(dt.hour)}:${_pad(dt.minute)}:${_pad(dt.second)}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  /// 適用済みマイグレーションを取得
  Future<Map<String, _MigrationInfo>> _getAppliedMigrations(
    PostgresDatabase db,
  ) async {
    // テーブルが存在するか確認
    final tableExists = await db.query('''
      SELECT EXISTS (
        SELECT FROM information_schema.tables
        WHERE table_name = '_aim_migrations'
      ) as exists
    ''');
    if (tableExists.isEmpty) {
      return {};
    }
    final existsValue = tableExists.first['exists'];
    final exists = existsValue == true || existsValue == 't';
    if (!exists) {
      return {};
    }

    final result = await db.query(
      'SELECT name, checksum, applied_at FROM _aim_migrations ORDER BY name',
    );

    return {
      for (final row in result)
        row['name'] as String: _MigrationInfo(
          name: row['name'] as String,
          checksum: row['checksum'] as String,
          appliedAt: _parseDateTime(row['applied_at']),
        ),
    };
  }

  DateTime _parseDateTime(dynamic value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.parse(value);
    throw ArgumentError('Cannot parse DateTime from: $value');
  }
}

class _MigrationInfo {
  final String name;
  final String checksum;
  final DateTime appliedAt;

  _MigrationInfo({
    required this.name,
    required this.checksum,
    required this.appliedAt,
  });
}
