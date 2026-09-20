import 'dart:convert';
import 'dart:io';

import 'package:aim_cli/aim_cli.dart';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late String previousCwd;

  /// Absolute path of the CLI entrypoint, resolved before any test moves
  /// the working directory.
  late String entrypoint;

  setUpAll(() {
    entrypoint = p.absolute('bin', 'aim.dart');
  });

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

  /// Runs `db:generate -n [migrationName]` as a child process, writing
  /// [answers] to its stdin one line each.
  ///
  /// The rename question is read from stdin, and a test cannot answer a
  /// prompt raised by the command running inside it.
  Future<ProcessResult> generateAnswering(
    String migrationName,
    List<String> answers,
  ) async {
    final process = await Process.start(Platform.resolvedExecutable, [
      'run',
      entrypoint,
      'db:generate',
      '-n',
      migrationName,
    ], workingDirectory: tmp.path);
    for (final answer in answers) {
      process.stdin.writeln(answer);
    }
    await process.stdin.close();
    final out = await process.stdout.transform(utf8.decoder).join();
    final err = await process.stderr.transform(utf8.decoder).join();
    return ProcessResult(process.pid, await process.exitCode, out, err);
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

  group('db:generate - a changed foreign key is replaced', () {
    test(
      'repointing it at another column drops and adds the constraint',
      () async {
        writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('parent')
final parent = (
  id: integer('id').primaryKey(),
  c1: varchar('c1', length: 20).unique(),
  c2: varchar('c2', length: 20).unique(),
);

@PgTable('child')
final child = (
  id: integer('id').primaryKey(),
  ref: varchar('ref', length: 20).references(() => parent.c1),
);
''');
        await generate('first');

        writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('parent')
final parent = (
  id: integer('id').primaryKey(),
  c1: varchar('c1', length: 20).unique(),
  c2: varchar('c2', length: 20).unique(),
);

@PgTable('child')
final child = (
  id: integer('id').primaryKey(),
  ref: varchar('ref', length: 20).references(() => parent.c2),
);
''');
        await generate('second');

        final up = upOf('second');
        final drop = up.indexOf(
          'ALTER TABLE child DROP CONSTRAINT IF EXISTS fk_child_ref;',
        );
        final add = up.indexOf('ADD CONSTRAINT fk_child_ref');
        expect(drop, isNonNegative);
        expect(add, isNonNegative);
        expect(
          drop,
          lessThan(add),
          reason:
              'Postgres has no statement that repoints a foreign key, so '
              'the old one has to go before the new one arrives',
        );
        expect(up, contains('REFERENCES parent(c2)'));
      },
    );

    test(
      'changing only the referential action replaces the constraint too',
      () async {
        writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('parent')
final parent = (
  id: integer('id').primaryKey(),
);

@PgTable('child')
final child = (
  id: integer('id').primaryKey(),
  parent_id: integer('parent_id').references(
    () => parent.id,
    onDelete: OnDeleteAction.cascade,
  ),
);
''');
        await generate('first');

        writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('parent')
final parent = (
  id: integer('id').primaryKey(),
);

@PgTable('child')
final child = (
  id: integer('id').primaryKey(),
  parent_id: integer('parent_id').references(
    () => parent.id,
    onDelete: OnDeleteAction.setNull,
  ),
);
''');
        await generate('second');

        final up = upOf('second');
        expect(up, contains('DROP CONSTRAINT IF EXISTS fk_child_parent_id;'));
        expect(up, contains('ON DELETE SET NULL'));
        expect(up, isNot(contains('ON DELETE CASCADE')));
      },
    );

    test('an unchanged foreign key produces no migration', () async {
      const schema = '''
import 'package:aim_orm/aim_orm.dart';

@PgTable('parent')
final parent = (
  id: integer('id').primaryKey(),
);

@PgTable('child')
final child = (
  id: integer('id').primaryKey(),
  parent_id: integer('parent_id').references(
    () => parent.id,
    onDelete: OnDeleteAction.cascade,
  ),
);
''';
      writeSchema(schema);
      await generate('first');
      writeSchema(schema);
      await generate('second');

      final files = Directory(p.join(tmp.path, 'db', 'migrations'))
          .listSync()
          .whereType<File>()
          .toList();
      expect(
        files,
        hasLength(1),
        reason: 'nothing changed, so there is nothing to migrate',
      );
    });
  });

  group('db:generate - nothing the schema declares is dropped in silence', () {
    test('a serial column asking for a default stops the command', () async {
      writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('things')
final things = (
  id: serial('id').withDefault(1),
  name: varchar('name', length: 20),
);
''');

      await expectLater(
        generate('first'),
        throwsA(
          isA<FormatException>()
              .having((e) => e.message, 'message', contains('serial'))
              .having((e) => e.message, 'message', contains('id'))
              .having((e) => e.message, 'message', contains('withDefault()')),
        ),
      );
    });

    test('a serial column without one is written as SERIAL', () async {
      writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('things')
final things = (
  id: serial('id').primaryKey(),
  name: varchar('name', length: 20),
);
''');
      await generate('first');

      final up = upOf('first');
      expect(up, contains('id SERIAL PRIMARY KEY'));
      expect(up, isNot(contains('DEFAULT')));
    });

    test('a reference through an import prefix is read', () async {
      writeSchemaFile('users.dart', '''
import 'package:aim_orm/aim_orm.dart';

@PgTable('pref_users')
final prefUsers = (
  id: integer('id').primaryKey(),
);
''');
      writeSchemaFile('posts.dart', '''
import 'package:aim_orm/aim_orm.dart';
import 'users.dart' as u;

@PgTable('pref_posts')
final prefPosts = (
  id: integer('id').primaryKey(),
  user_id: integer('user_id').references(() => u.prefUsers.id),
);
''');
      await generate('first');

      expect(upOf('first'), contains('REFERENCES pref_users(id)'));
    });

    test(
      'a reference the reader cannot make sense of stops the command',
      () async {
        writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('users')
final users = (
  id: integer('id').primaryKey(),
);

@PgTable('posts')
final posts = (
  id: integer('id').primaryKey(),
  user_id: integer('user_id').references(users.id),
);
''');

        await expectLater(
          generate('first'),
          throwsA(
            isA<FormatException>()
                .having((e) => e.message, 'message', contains('user_id'))
                .having((e) => e.message, 'message', contains('schema.dart'))
                .having(
                  (e) => e.message,
                  'message',
                  contains('references(() => users.id)'),
                ),
          ),
        );
      },
    );

    test('withDefaultNow becomes a default in the SQL', () async {
      writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('users')
final users = (
  id: integer('id').primaryKey(),
  created_at: timestamp('created_at').withDefaultNow(),
);
''');
      await generate('first');

      expect(
        upOf('first'),
        contains('created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP'),
      );
    });

    test('a method the reader does not know stops the command', () async {
      writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('users')
final users = (
  id: integer('id').primaryKey(),
  name: varchar('name', length: 20).withCollation('C'),
);
''');

      await expectLater(
        generate('first'),
        throwsA(
          isA<FormatException>()
              .having((e) => e.message, 'message', contains('withCollation'))
              .having((e) => e.message, 'message', contains('name'))
              .having((e) => e.message, 'message', contains('schema.dart')),
        ),
      );
    });

    test('renaming a unique column takes the constraint with it', () async {
      writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('ren_users')
final renUsers = (
  id: integer('id').primaryKey(),
  code: varchar('code', length: 20).unique(),
);
''');
      await generate('first');

      writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('ren_users')
final renUsers = (
  id: integer('id').primaryKey(),
  code2: varchar('code2', length: 20).unique(),
);
''');
      final result = await generateAnswering('second', ['y']);
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');

      final up = upOf('second');
      final dropOld = up.indexOf(
        'DROP CONSTRAINT IF EXISTS uq_ren_users_code;',
      );
      final rename = up.indexOf('RENAME COLUMN code TO code2;');
      final addNew = up.indexOf(
        'ADD CONSTRAINT uq_ren_users_code2 UNIQUE (code2);',
      );
      expect(dropOld, isNonNegative);
      expect(rename, isNonNegative);
      expect(addNew, isNonNegative);
      expect(
        dropOld,
        lessThan(rename),
        reason: 'the old constraint is named after the old column',
      );
      expect(
        rename,
        lessThan(addNew),
        reason: 'the new constraint is named after the new column',
      );
    });

    test('a reference with its action written first is read', () async {
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
    onDelete: OnDeleteAction.cascade,
    () => users.id,
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

    test('a chain wrapped in brackets keeps its type', () async {
      writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('users')
final users = (
  id: (integer('id')).primaryKey(),
);
''');
      await generate('first');

      final up = upOf('first');
      expect(up, contains('id INTEGER PRIMARY KEY'));
      expect(up, isNot(contains('id TEXT')));
    });

    test('copyWith points at the modifier to use instead', () async {
      writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('users')
final users = (
  id: integer('id').copyWith(isPrimaryKey: true),
);
''');

      await expectLater(
        generate('first'),
        throwsA(
          isA<FormatException>()
              .having((e) => e.message, 'message', contains('copyWith'))
              .having((e) => e.message, 'message', contains('primaryKey()')),
        ),
      );
    });

    test('a field that is not a column definition stops the command', () async {
      writeSchema('''
import 'package:aim_orm/aim_orm.dart';

const shared = 1;

@PgTable('users')
final users = (
  id: integer('id').primaryKey(),
  count: shared,
);
''');

      await expectLater(
        generate('first'),
        throwsA(
          isA<FormatException>()
              .having((e) => e.message, 'message', contains('count'))
              .having((e) => e.message, 'message', contains('schema.dart')),
        ),
      );
    });

    test('a nested record stops the command too', () async {
      writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('users')
final users = (
  id: integer('id').primaryKey(),
  nested: (a: integer('a'), b: integer('b')),
);
''');

      await expectLater(
        generate('first'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('nested'),
          ),
        ),
      );
    });
  });
}
