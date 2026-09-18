import 'dart:io';

import 'package:aim_cli/aim_cli.dart';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late String previousCwd;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('aim_db_constraints_');
    previousCwd = Directory.current.path;
    Directory.current = tmp;

    File(p.join(tmp.path, 'pubspec.yaml'))
        .writeAsStringSync('name: test_project\n');
  });

  tearDown(() async {
    Directory.current = previousCwd;
    await tmp.delete(recursive: true);
  });

  void writeSchema(String contents) {
    final schemaDir = Directory(p.join(tmp.path, 'lib', 'schema'));
    schemaDir.createSync(recursive: true);
    File(p.join(schemaDir.path, 'schema.dart')).writeAsStringSync(contents);
  }

  /// Runs `db:generate -n [migrationName]`.
  ///
  /// Generated file names carry a timestamp down to the second, so two runs
  /// inside one test can land on the same name. Naming each run keeps the
  /// two files apart.
  Future<void> generate(String migrationName) {
    final runner = CommandRunner<void>('aim', 'test')
      ..addCommand(DbGenerateCommand());
    return runner.run(['db:generate', '-n', migrationName]);
  }

  File migrationNamed(String migrationName) {
    final dir = Directory(p.join(tmp.path, 'db', 'migrations'));
    final matches = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('_$migrationName.sql'))
        .toList();
    expect(
      matches,
      hasLength(1),
      reason:
          'expected one migration named $migrationName, '
          'found ${matches.map((f) => p.basename(f.path)).toList()}',
    );
    return matches.single;
  }

  /// The text between the `-- UP` and `-- DOWN` markers.
  String upOf(String migrationName) {
    final content = migrationNamed(migrationName).readAsStringSync();
    final up = RegExp(r'^--\s*UP\s*$', multiLine: true).firstMatch(content);
    final down = RegExp(r'^--\s*DOWN\s*$', multiLine: true).firstMatch(content);
    expect(up, isNotNull);
    expect(down, isNotNull);
    return content.substring(up!.end, down!.start);
  }

  group('db:generate - constraints are created with a name', () {
    test('a foreign key written inside CREATE TABLE carries the name the '
        'generator drops it by', () async {
      writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('users')
final users = (
  id: integer('id').primaryKey(),
);

@PgTable('posts')
final posts = (
  id: integer('id').primaryKey(),
  user_id: integer('user_id').references(
    () => users.id,
    onDelete: OnDeleteAction.cascade,
  ),
);
''');
      await generate('first');

      expect(
        upOf('first'),
        contains(
          'CONSTRAINT fk_posts_user_id FOREIGN KEY (user_id) '
          'REFERENCES users(id) ON DELETE CASCADE',
        ),
      );
    });

    test('a unique column becomes a named table constraint, not a keyword '
        'after the column', () async {
      writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('users')
final users = (
  id: integer('id').primaryKey(),
  email: varchar('email', length: 255).unique(),
);
''');
      await generate('first');

      final up = upOf('first');
      expect(up, contains('CONSTRAINT uq_users_email UNIQUE (email)'));
      expect(up, contains('email VARCHAR(255) NOT NULL'));
      expect(
        up,
        isNot(contains('VARCHAR(255) UNIQUE')),
        reason:
            'an unnamed constraint is named by Postgres, and then the '
            'statement that drops it cannot find it',
      );
    });

    test(
      'adding a unique column adds the column and then the constraint',
      () async {
        writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('users')
final users = (
  id: integer('id').primaryKey(),
);
''');
        await generate('first');

        // Nullable so db:generate does not stop to ask about a NOT NULL
        // column with no default.
        writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('users')
final users = (
  id: integer('id').primaryKey(),
  email: varchar('email', length: 255).nullable().unique(),
);
''');
        await generate('second');

        final up = upOf('second');
        expect(
          up,
          contains('ALTER TABLE users ADD COLUMN email VARCHAR(255);'),
        );
        expect(
          up,
          contains(
            'ALTER TABLE users ADD CONSTRAINT uq_users_email UNIQUE (email);',
          ),
        );
      },
    );

    test('a primary key stays on the column', () async {
      writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('users')
final users = (
  id: integer('id').primaryKey().unique(),
);
''');
      await generate('first');

      final up = upOf('first');
      expect(up, contains('id INTEGER PRIMARY KEY'));
      expect(
        up,
        isNot(contains('uq_users_id')),
        reason:
            'a primary key is already unique, so a second constraint '
            'would only add a redundant index',
      );
    });
  });

  group('db:generate - constraints are dropped under both names', () {
    test('a unique constraint added when the table was created is dropped '
        'under the generator name and the name Postgres gives', () async {
      writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('users')
final users = (
  id: integer('id').primaryKey(),
  email: varchar('email', length: 255).unique(),
);
''');
      await generate('first');

      writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('users')
final users = (
  id: integer('id').primaryKey(),
  email: varchar('email', length: 255),
);
''');
      await generate('second');

      final up = upOf('second');
      expect(
        up,
        contains('ALTER TABLE users DROP CONSTRAINT IF EXISTS uq_users_email;'),
      );
      expect(
        up,
        contains(
          'ALTER TABLE users DROP CONSTRAINT IF EXISTS users_email_key;',
        ),
        reason:
            'a table created before the generator named its constraints '
            'carries the name Postgres chose',
      );
    });

    test('a foreign key is dropped under both names too', () async {
      writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('users')
final users = (
  id: integer('id').primaryKey(),
);

@PgTable('posts')
final posts = (
  id: integer('id').primaryKey(),
  user_id: integer('user_id').references(() => users.id),
);
''');
      await generate('first');

      writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('users')
final users = (
  id: integer('id').primaryKey(),
);

@PgTable('posts')
final posts = (
  id: integer('id').primaryKey(),
  user_id: integer('user_id'),
);
''');
      await generate('second');

      final up = upOf('second');
      expect(
        up,
        contains(
          'ALTER TABLE posts DROP CONSTRAINT IF EXISTS fk_posts_user_id;',
        ),
      );
      expect(
        up,
        contains(
          'ALTER TABLE posts DROP CONSTRAINT IF EXISTS posts_user_id_fkey;',
        ),
      );
    });
  });
}
