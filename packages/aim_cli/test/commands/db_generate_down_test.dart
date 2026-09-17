import 'dart:io';

import 'package:aim_cli/aim_cli.dart';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late String previousCwd;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('aim_db_generate_down_');
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

  /// The text after the `-- DOWN` marker.
  String downOf(String migrationName) {
    final content = migrationNamed(migrationName).readAsStringSync();
    final down = RegExp(r'^--\s*DOWN\s*$', multiLine: true).firstMatch(content);
    expect(down, isNotNull);
    return content.substring(down!.end);
  }

  group('db:generate - a default the analyzer could not read', () {
    test('never reaches the SQL as the internal marker', () async {
      writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('users')
final users = (
  id: integer('id').primaryKey(),
  created_at: timestamp('created_at'),
);
''');
      await generate('first');

      // withDefault() given something that is not a literal: the analyzer
      // records that a default exists but cannot record its value.
      writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('users')
final users = (
  id: integer('id').primaryKey(),
  created_at: timestamp('created_at').withDefault(clockNow()),
);
''');
      await generate('second');

      final up = upOf('second');
      expect(up, isNot(contains('__HAS_DEFAULT__')));
      expect(up, contains('Cannot set the default for "created_at"'));
    });
  });

  group('db:generate - DOWN restores what UP removed', () {
    test('dropping a table writes the whole CREATE TABLE back', () async {
      writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('users')
final users = (
  id: integer('id').primaryKey(),
);

@PgTable('posts')
final posts = (
  id: integer('id').primaryKey(),
  title: text('title'),
  slug: varchar('slug').indexed(),
);
''');
      await generate('first');

      writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('users')
final users = (
  id: integer('id').primaryKey(),
);
''');
      await generate('second');

      final down = downOf('second');
      expect(down, isNot(contains('TODO')));
      expect(down, contains('CREATE TABLE posts ('));
      expect(down, contains('title TEXT NOT NULL'));
      expect(down, contains('CREATE INDEX idx_posts_slug ON posts (slug);'));
      expect(down, contains('Rows removed by the UP section'));
    });

    test(
      'dropping a column writes ADD COLUMN with the old definition',
      () async {
        writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('users')
final users = (
  id: integer('id').primaryKey(),
  bio: text('bio').nullable(),
);
''');
        await generate('first');

        writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('users')
final users = (
  id: integer('id').primaryKey(),
);
''');
        await generate('second');

        final down = downOf('second');
        expect(down, isNot(contains('TODO')));
        expect(down, contains('ALTER TABLE users ADD COLUMN bio TEXT;'));
        expect(down, contains('Values removed by the UP section'));
        // A nullable column can be added back to a table that has rows.
        expect(down, isNot(contains('NOT NULL with no default')));
      },
    );

    test('dropping a NOT NULL column with no default says the statement '
        'will fail on a table with rows', () async {
      writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('users')
final users = (
  id: integer('id').primaryKey(),
  age: integer('age'),
);
''');
      await generate('first');

      writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('users')
final users = (
  id: integer('id').primaryKey(),
);
''');
      await generate('second');

      final down = downOf('second');
      expect(
        down,
        contains('ALTER TABLE users ADD COLUMN age INTEGER NOT NULL;'),
      );
      expect(down, contains('NOT NULL with no default'));
    });

    test('dropping a foreign key writes ADD CONSTRAINT back with its '
        'referential actions', () async {
      writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('users')
final users = (
  id: integer('id').primaryKey(),
);

@PgTable('posts')
final posts = (
  id: integer('id').primaryKey(),
  user_id: integer('user_id').references(() => users.id, onDelete: OnDeleteAction.cascade),
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

      final down = downOf('second');
      expect(down, isNot(contains('TODO')));
      expect(
        down,
        contains(
          'ALTER TABLE posts ADD CONSTRAINT fk_posts_user_id '
          'FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;',
        ),
      );
    });

    test('dropping an index writes CREATE INDEX back', () async {
      writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('users')
final users = (
  id: integer('id').primaryKey(),
  name: varchar('name').indexed(),
);
''');
      await generate('first');

      writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('users')
final users = (
  id: integer('id').primaryKey(),
  name: varchar('name'),
);
''');
      await generate('second');

      final down = downOf('second');
      expect(down, isNot(contains('TODO')));
      expect(down, contains('CREATE INDEX idx_users_name ON users (name);'));
    });

    test('dropping a unique constraint writes ADD CONSTRAINT back', () async {
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

      final down = downOf('second');
      expect(down, isNot(contains('TODO')));
      expect(
        down,
        contains(
          'ALTER TABLE users ADD CONSTRAINT uq_users_email '
          'UNIQUE (email);',
        ),
      );
    });

    test('dropping a default writes the old value back', () async {
      writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('users')
final users = (
  id: integer('id').primaryKey(),
  status: varchar('status').withDefault('draft'),
);
''');
      await generate('first');

      writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('users')
final users = (
  id: integer('id').primaryKey(),
  status: varchar('status'),
);
''');
      await generate('second');

      final down = downOf('second');
      expect(down, isNot(contains('TODO')));
      expect(
        down,
        contains(
          "ALTER TABLE users ALTER COLUMN status "
          "SET DEFAULT 'draft';",
        ),
      );
    });

    test(
      'changing a default writes the old value back, not DROP DEFAULT',
      () async {
        writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('users')
final users = (
  id: integer('id').primaryKey(),
  status: varchar('status').withDefault('draft'),
);
''');
        await generate('first');

        writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('users')
final users = (
  id: integer('id').primaryKey(),
  status: varchar('status').withDefault('published'),
);
''');
        await generate('second');

        final down = downOf('second');
        expect(
          down,
          contains(
            "ALTER TABLE users ALTER COLUMN status "
            "SET DEFAULT 'draft';",
          ),
        );
        expect(down, isNot(contains('DROP DEFAULT')));
      },
    );

    test('creating a table is undone by DROP TABLE alone', () async {
      writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('users')
final users = (
  id: integer('id').primaryKey(),
  name: varchar('name').indexed(),
);
''');
      await generate('first');

      final down = downOf('first');
      expect(down, contains('DROP TABLE IF EXISTS users;'));
      // Dropping the table takes its indexes with it.
      expect(down, isNot(contains('DROP INDEX')));
    });

    test('the UP section carries no restore notes', () async {
      writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('users')
final users = (
  id: integer('id').primaryKey(),
  bio: text('bio').nullable(),
);
''');
      await generate('first');

      writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('users')
final users = (
  id: integer('id').primaryKey(),
);
''');
      await generate('second');

      final up = upOf('second');
      expect(up, contains('ALTER TABLE users DROP COLUMN bio;'));
      expect(up, isNot(contains('Values removed by the UP section')));
    });
  });

  group('db:generate - DOWN statement order', () {
    test('a dropped column is added back before its index', () async {
      writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('users')
final users = (
  id: integer('id').primaryKey(),
  name: varchar('name').indexed(),
);
''');
      await generate('first');

      writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('users')
final users = (
  id: integer('id').primaryKey(),
);
''');
      await generate('second');

      final down = downOf('second');
      final addColumn = down.indexOf('ADD COLUMN name');
      final createIndex = down.indexOf('CREATE INDEX idx_users_name');
      expect(addColumn, isNonNegative);
      expect(createIndex, isNonNegative);
      expect(
        addColumn,
        lessThan(createIndex),
        reason: 'an index cannot be created on a column that is not back yet',
      );
    });

    test("an added column's index is dropped before the column", () async {
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
  name: varchar('name').nullable().indexed(),
);
''');
      await generate('second');

      final down = downOf('second');
      final dropIndex = down.indexOf('DROP INDEX idx_users_name');
      final dropColumn = down.indexOf('DROP COLUMN name');
      expect(dropIndex, isNonNegative);
      expect(dropColumn, isNonNegative);
      expect(dropIndex, lessThan(dropColumn));
    });

    test('a table a foreign key points at is created before the table '
        'holding it', () async {
      // posts is declared first on purpose: the table order of the
      // snapshot follows declaration order, so restoring in snapshot order
      // would create posts before the users row it references.
      writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('posts')
final posts = (
  id: integer('id').primaryKey(),
  user_id: integer('user_id').references(() => users.id),
);

@PgTable('users')
final users = (
  id: integer('id').primaryKey(),
);
''');
      await generate('first');

      writeSchema('''
import 'package:aim_orm/aim_orm.dart';
''');
      await generate('second');

      final down = downOf('second');
      final createUsers = down.indexOf('CREATE TABLE users (');
      final createPosts = down.indexOf('CREATE TABLE posts (');
      expect(createUsers, isNonNegative);
      expect(createPosts, isNonNegative);
      expect(
        createUsers,
        lessThan(createPosts),
        reason:
            'CREATE TABLE writes its foreign keys inline, so the '
            'referenced table has to exist first',
      );
    });

    test('tables created together are dropped dependents first', () async {
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

      final down = downOf('first');
      final dropPosts = down.indexOf('DROP TABLE IF EXISTS posts;');
      final dropUsers = down.indexOf('DROP TABLE IF EXISTS users;');
      expect(dropPosts, isNonNegative);
      expect(dropUsers, isNonNegative);
      expect(
        dropPosts,
        lessThan(dropUsers),
        reason:
            'a table cannot be dropped while another table still '
            'references it',
      );
    });

    test('a self-referencing table still gets created', () async {
      writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('nodes')
final nodes = (
  id: integer('id').primaryKey(),
  parent_id: integer('parent_id').references(() => nodes.id),
);
''');
      await generate('first');

      writeSchema('''
import 'package:aim_orm/aim_orm.dart';
''');
      await generate('second');

      final down = downOf('second');
      expect(down, contains('CREATE TABLE nodes ('));
    });
  });

  group('db:generate - DOWN reverses an altered column type', () {
    test('a column type change goes back to the old type', () async {
      writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('users')
final users = (
  id: integer('id').primaryKey(),
  code: varchar('code', length: 10),
);
''');
      await generate('first');

      writeSchema('''
import 'package:aim_orm/aim_orm.dart';

@PgTable('users')
final users = (
  id: integer('id').primaryKey(),
  code: varchar('code', length: 40),
);
''');
      await generate('second');

      expect(
        upOf('second'),
        contains('ALTER TABLE users ALTER COLUMN code TYPE VARCHAR(40);'),
      );
      expect(
        downOf('second'),
        contains('ALTER TABLE users ALTER COLUMN code TYPE VARCHAR(10);'),
      );
    });
  });
}
