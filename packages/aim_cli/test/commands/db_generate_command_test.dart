import 'dart:io';

import 'package:aim_cli/aim_cli.dart';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late String previousCwd;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('aim_db_generate_');
    previousCwd = Directory.current.path;
    Directory.current = tmp;

    File(p.join(tmp.path, 'pubspec.yaml'))
        .writeAsStringSync('name: test_project\n');
  });

  tearDown(() async {
    Directory.current = previousCwd;
    await tmp.delete(recursive: true);
  });

  Future<void> generate() {
    final runner = CommandRunner<void>('aim', 'test')
      ..addCommand(DbGenerateCommand());
    return runner.run(['db:generate']);
  }

  void writeSchema(String contents) {
    final schemaDir = Directory(p.join(tmp.path, 'lib', 'schema'));
    schemaDir.createSync(recursive: true);
    File(p.join(schemaDir.path, 'schema.dart')).writeAsStringSync(contents);
  }

  /// The migration file db:generate just wrote. Its name is timestamped,
  /// so it has to be located rather than opened by a fixed path.
  String readGeneratedMigration() {
    final migrationsDir = Directory(p.join(tmp.path, 'db', 'migrations'));
    final files = migrationsDir.listSync().whereType<File>().toList();
    expect(files, hasLength(1));
    return files.single.readAsStringSync();
  }

  group('db:generate - CREATE TABLE column rendering', () {
    test('a varchar column with no length renders VARCHAR with no '
        'parentheses, not VARCHAR(null) or a guessed length', () async {
      writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('users')
final users = (
  id: integer('id').primaryKey(),
  gender: varchar('gender').nullable(),
);
''');

      await generate();

      final sql = readGeneratedMigration();
      expect(sql, contains('gender VARCHAR\n'));
      expect(sql, isNot(contains('VARCHAR(null)')));
      expect(sql, isNot(contains('VARCHAR(255)')));
    });
  });
}
