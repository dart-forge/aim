@Tags(['integration'])
library;

import 'dart:io';

import 'package:aim_postgres/aim_postgres.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'docker_stack.dart';

void main() {
  /// Absolute path of the CLI entrypoint, resolved before any test changes
  /// directories.
  late String entrypoint;
  late PostgresDatabase db;

  setUpAll(() async {
    entrypoint = p.absolute('bin', 'aim.dart');
    await ensurePostgresStack();
    db = await reportPortIfTaken(() => PostgresDatabase.connect(databaseUrl));
  });

  tearDownAll(() async {
    await db.close();
  });

  setUp(() async {
    // Every test starts from an empty database: these suites share one
    // container, and a leftover table would make the next test lie.
    await db.execute('DROP TABLE IF EXISTS widgets');
    await db.execute('DROP TABLE IF EXISTS gadgets');
    await db.execute('DROP TABLE IF EXISTS _aim_migrations');
  });

  /// A throwaway project directory holding one migration file.
  Future<Directory> project(String migrationBody) async {
    final dir = await Directory.systemTemp.createTemp('aim_cli_rollback_');
    File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('''
name: rollback_test_project

aim:
  database:
    url: $databaseUrl
''');
    final migrations = Directory(p.join(dir.path, 'db', 'migrations'))
      ..createSync(recursive: true);
    File(p.join(migrations.path, '20260101000000_widgets.sql'))
        .writeAsStringSync(migrationBody);
    addTearDown(() => dir.delete(recursive: true));
    return dir;
  }

  /// Runs the CLI in [dir] as a child process.
  ///
  /// db:rollback calls exit() on failure, which would take the test runner
  /// with it if the command ran in this process. A child process also
  /// leaves stdin closed, so a prompt reads as "no".
  Future<ProcessResult> aim(List<String> args, Directory dir) => Process.run(
    Platform.resolvedExecutable,
    ['run', entrypoint, ...args],
    workingDirectory: dir.path,
  );

  Future<bool> tableExists(String name) async {
    final rows = await db.query(
      '''
      SELECT EXISTS (
        SELECT FROM information_schema.tables WHERE table_name = :name
      ) AS present
      ''',
      params: {'name': name},
    );
    final value = rows.first['present'];
    return value == true || value == 't';
  }

  Future<List<String>> appliedMigrations() async {
    if (!await tableExists('_aim_migrations')) return [];
    final rows = await db.query(
      'SELECT name FROM _aim_migrations ORDER BY name',
    );
    return rows.map((row) => row['name'] as String).toList();
  }

  test(
    'a DOWN section that runs takes the schema and the history back',
    () async {
      final dir = await project('''
-- UP
CREATE TABLE widgets (id SERIAL PRIMARY KEY, name TEXT NOT NULL);

-- DOWN
DROP TABLE IF EXISTS widgets;
''');

      final migrate = await aim(['db:migrate'], dir);
      expect(migrate.exitCode, 0, reason: '${migrate.stdout}${migrate.stderr}');
      expect(await tableExists('widgets'), isTrue);
      expect(await appliedMigrations(), hasLength(1));

      final rollback = await aim(['db:rollback'], dir);
      expect(
        rollback.exitCode,
        0,
        reason: '${rollback.stdout}${rollback.stderr}',
      );
      expect(await tableExists('widgets'), isFalse);
      expect(await appliedMigrations(), isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('a DOWN section that fails part way through changes nothing', () async {
    final dir = await project('''
-- UP
CREATE TABLE widgets (id SERIAL PRIMARY KEY);
CREATE TABLE gadgets (id SERIAL PRIMARY KEY);

-- DOWN
DROP TABLE IF EXISTS gadgets;
DROP TABLE no_such_table_here;
''');

    final migrate = await aim(['db:migrate'], dir);
    expect(migrate.exitCode, 0, reason: '${migrate.stdout}${migrate.stderr}');

    final rollback = await aim(['db:rollback'], dir);
    expect(rollback.exitCode, isNot(0));
    // The first statement succeeded on its own, so without a transaction
    // gadgets would be gone and the history row would still be there.
    expect(await tableExists('gadgets'), isTrue);
    expect(await tableExists('widgets'), isTrue);
    expect(await appliedMigrations(), hasLength(1));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test(
    'a DOWN section that is only comments is not reported as rolled back',
    () async {
      final dir = await project('''
-- UP
CREATE TABLE widgets (id SERIAL PRIMARY KEY);

-- DOWN
-- TODO: Cannot restore dropped table "widgets" without schema backup
''');

      final migrate = await aim(['db:migrate'], dir);
      expect(migrate.exitCode, 0, reason: '${migrate.stdout}${migrate.stderr}');

      final rollback = await aim(['db:rollback'], dir);
      expect(rollback.exitCode, isNot(0));
      expect(
        rollback.stdout,
        contains('Cannot rollback this migration automatically.'),
      );
      expect(await tableExists('widgets'), isTrue);
      expect(await appliedMigrations(), hasLength(1));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('a migration marked to run outside a transaction may use a statement '
      'a transaction forbids', () async {
    final dir = await project('''
-- UP
-- aim: no-transaction
CREATE TABLE widgets (id SERIAL PRIMARY KEY, name TEXT NOT NULL);
CREATE INDEX CONCURRENTLY idx_widgets_name ON widgets (name);

-- DOWN
DROP TABLE IF EXISTS widgets;
''');

    final migrate = await aim(['db:migrate'], dir);
    expect(migrate.exitCode, 0, reason: '${migrate.stdout}${migrate.stderr}');
    expect(await tableExists('widgets'), isTrue);
    expect(await appliedMigrations(), hasLength(1));
  });

  test('a statement a transaction forbids is told how to run', () async {
    final dir = await project('''
-- UP
CREATE TABLE widgets (id SERIAL PRIMARY KEY, name TEXT NOT NULL);
CREATE INDEX CONCURRENTLY idx_widgets_name ON widgets (name);

-- DOWN
DROP TABLE IF EXISTS widgets;
''');

    final migrate = await aim(['db:migrate'], dir);
    expect(migrate.exitCode, isNot(0));
    expect(migrate.stdout, contains('-- aim: no-transaction'));
    expect(await tableExists('widgets'), isFalse);
    expect(await appliedMigrations(), isEmpty);
  });

  test('the notes in a DOWN section are printed before it runs', () async {
    final dir = await project('''
-- UP
DROP TABLE IF EXISTS widgets;

-- DOWN
-- Restores the table structure only. Rows removed by the UP section
-- are not recovered.
CREATE TABLE widgets (id SERIAL PRIMARY KEY);
''');

    final migrate = await aim(['db:migrate'], dir);
    expect(migrate.exitCode, 0, reason: '${migrate.stdout}${migrate.stderr}');

    final rollback = await aim(['db:rollback'], dir);
    expect(
      rollback.exitCode,
      0,
      reason: '${rollback.stdout}${rollback.stderr}',
    );
    final output = rollback.stdout as String;
    final note = output.indexOf('Rows removed by the UP section');
    final done = output.indexOf('Rolled back:');
    expect(note, isNonNegative);
    expect(done, isNonNegative);
    expect(
      note,
      lessThan(done),
      reason: 'a precondition read after the fact is no use',
    );
    expect(await tableExists('widgets'), isTrue);
  });
}
