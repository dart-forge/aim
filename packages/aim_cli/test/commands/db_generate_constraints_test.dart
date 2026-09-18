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

  void writeSchemaFile(String fileName, String contents) {
    final schemaDir = Directory(p.join(tmp.path, 'lib', 'schema'));
    schemaDir.createSync(recursive: true);
    File(p.join(schemaDir.path, fileName)).writeAsStringSync(contents);
  }

  void writeSchema(String contents) => writeSchemaFile('schema.dart', contents);

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

  group('db:generate - a reference names the table and column in SQL', () {
    test('uses the table name, not the Dart variable name', () async {
      writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('ord_users')
final ordUsers = (
  id: integer('id').primaryKey(),
);

@PgTable('ord_posts')
final ordPosts = (
  id: integer('id').primaryKey(),
  user_id: integer('user_id').references(() => ordUsers.id),
);
''');
      await generate('first');

      final up = upOf('first');
      expect(up, contains('REFERENCES ord_users(id)'));
      expect(up, isNot(contains('REFERENCES ordUsers')));
    });

    test('uses the column name, not the record field name', () async {
      writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('users')
final users = (
  key: integer('user_key').primaryKey(),
);

@PgTable('posts')
final posts = (
  id: integer('id').primaryKey(),
  owner: integer('owner_key').references(() => users.key),
);
''');
      await generate('first');

      final up = upOf('first');
      expect(up, contains('REFERENCES users(user_key)'));
      expect(up, isNot(contains('REFERENCES users(key)')));
    });

    test('resolves a table that references itself', () async {
      writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('nodes')
final nodes = (
  id: integer('id').primaryKey(),
  parent_id: integer('parent_id').nullable().references(() => nodes.id),
);
''');
      await generate('first');

      expect(upOf('first'), contains('REFERENCES nodes(id)'));
    });

    test('stops when the referenced variable is not a table, naming the '
        'file and the reference', () async {
      writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('posts')
final posts = (
  id: integer('id').primaryKey(),
  user_id: integer('user_id').references(() => missingTable.id),
);
''');

      await expectLater(
        generate('first'),
        throwsA(
          isA<FormatException>()
              .having((e) => e.message, 'message', contains('missingTable'))
              .having((e) => e.message, 'message', contains('posts.user_id'))
              .having((e) => e.message, 'message', contains('schema.dart')),
        ),
      );
    });

    test('stops when the referenced field does not exist, listing the '
        'fields that do', () async {
      writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('users')
final users = (
  id: integer('id').primaryKey(),
  email: varchar('email', length: 255).nullable(),
);

@PgTable('posts')
final posts = (
  id: integer('id').primaryKey(),
  user_id: integer('user_id').references(() => users.nope),
);
''');

      await expectLater(
        generate('first'),
        throwsA(
          isA<FormatException>()
              .having((e) => e.message, 'message', contains('nope'))
              .having((e) => e.message, 'message', contains('id, email')),
        ),
      );
    });

    test('a variable declared in two files resolves within the file that '
        'wrote the reference', () async {
      writeSchemaFile('a.dart', '''
import 'package:aim_orm/aim_orm.dart';

@PgTable('a_users')
final users = (
  a_id: integer('a_id').primaryKey(),
);

@PgTable('a_posts')
final aPosts = (
  id: integer('id').primaryKey(),
  user_id: integer('user_id').references(() => users.a_id),
);
''');
      writeSchemaFile('b.dart', '''
import 'package:aim_orm/aim_orm.dart';

@PgTable('b_users')
final users = (
  a_id: integer('a_id').primaryKey(),
);
''');
      await generate('first');

      final up = upOf('first');
      expect(up, contains('REFERENCES a_users(a_id)'));
      expect(up, isNot(contains('REFERENCES b_users')));
    });

    test('a variable declared in two other files stops the command, naming '
        'them', () async {
      writeSchemaFile('a.dart', '''
import 'package:aim_orm/aim_orm.dart';

@PgTable('a_users')
final users = (
  id: integer('id').primaryKey(),
);
''');
      writeSchemaFile('b.dart', '''
import 'package:aim_orm/aim_orm.dart';

@PgTable('b_users')
final users = (
  id: integer('id').primaryKey(),
);
''');
      writeSchemaFile('c.dart', '''
import 'package:aim_orm/aim_orm.dart';

@PgTable('c_posts')
final cPosts = (
  id: integer('id').primaryKey(),
  user_id: integer('user_id').references(() => users.id),
);
''');

      await expectLater(
        generate('first'),
        throwsA(
          isA<FormatException>()
              .having((e) => e.message, 'message', contains('a.dart'))
              .having((e) => e.message, 'message', contains('b.dart'))
              .having(
                (e) => e.message,
                'message',
                contains('declared more than once'),
              ),
        ),
      );
    });

    test('two records claiming one table stop the command', () async {
      writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('shared')
final varA = (
  a_id: integer('a_id').primaryKey(),
);

@PgTable('shared')
final varB = (
  b_id: integer('b_id').primaryKey(),
);
''');

      await expectLater(
        generate('first'),
        throwsA(
          isA<FormatException>()
              .having((e) => e.message, 'message', contains('shared'))
              .having((e) => e.message, 'message', contains('varA'))
              .having((e) => e.message, 'message', contains('varB')),
        ),
      );
    });

    test('resolves the field against the referenced table, not the one '
        'holding the key', () async {
      writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('users')
final users = (
  key: integer('user_key').primaryKey(),
);

@PgTable('posts')
final posts = (
  key: integer('post_key').primaryKey(),
  owner: integer('owner_key').references(() => users.key),
);
''');
      await generate('first');

      final up = upOf('first');
      expect(up, contains('REFERENCES users(user_key)'));
      expect(
        up,
        isNot(contains('REFERENCES users(post_key)')),
        reason:
            'both tables have a field called key, and only the '
            'referenced one decides the column',
      );
    });
  });
}
