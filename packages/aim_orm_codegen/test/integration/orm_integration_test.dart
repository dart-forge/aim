@Tags(['integration'])
library;

import 'package:aim_postgres/aim_postgres.dart';
import 'package:test/test.dart';

import 'docker_stack.dart';
import 'fixtures/tables.dart';

void main() {
  late PostgresDatabase db;

  setUpAll(() async {
    await ensurePostgresStack();
    db = await reportPortIfTaken(
      () => PostgresDatabase.connect(
        'postgresql://test:test@localhost:15437/test_db',
      ),
      port: 15437,
    );

    // Create tables in correct order (respecting FK constraints)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id UUID PRIMARY KEY,
        name VARCHAR(255) NOT NULL,
        age INT,
        active INT NOT NULL,
        created_at TIMESTAMP NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS posts (
        id UUID PRIMARY KEY,
        title VARCHAR(255) NOT NULL,
        content TEXT NOT NULL,
        user_id UUID NOT NULL REFERENCES users(id),
        created_at TIMESTAMP NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS articles (
        id UUID PRIMARY KEY,
        title VARCHAR(255) NOT NULL,
        author_id UUID REFERENCES users(id),
        created_at TIMESTAMP NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS comments (
        id UUID PRIMARY KEY,
        content TEXT NOT NULL,
        post_id UUID NOT NULL REFERENCES posts(id),
        user_id UUID NOT NULL REFERENCES users(id),
        created_at TIMESTAMP NOT NULL
      )
    ''');
  });

  setUp(() async {
    // Clean up in reverse FK order
    await db.execute('TRUNCATE TABLE comments, articles, posts, users CASCADE');

    // Insert seed data
    await db.execute("""
      INSERT INTO users (id, name, age, active, created_at) VALUES
        ('11111111-1111-1111-1111-111111111111', 'Alice', 30, 1, '2024-01-01 10:00:00'),
        ('22222222-2222-2222-2222-222222222222', 'Bob', 25, 0, '2024-01-02 10:00:00'),
        ('33333333-3333-3333-3333-333333333333', 'Charlie', NULL, 1, '2024-01-03 10:00:00')
    """);

    await db.execute("""
      INSERT INTO posts (id, title, content, user_id, created_at) VALUES
        ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'First Post', 'Content of first post', '11111111-1111-1111-1111-111111111111', '2024-01-10 10:00:00'),
        ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Second Post', 'Content of second post', '22222222-2222-2222-2222-222222222222', '2024-01-11 10:00:00')
    """);
  });

  tearDownAll(() async {
    await db.execute(
      'DROP TABLE IF EXISTS comments, articles, posts, users CASCADE',
    );
    await db.close();
  });

  group('SELECT', () {
    test('select() returns all rows', () async {
      final rows = await db.users.select();
      expect(rows.length, 3);
    });

    test('select().where() with eq', () async {
      final rows = await db.users.select().where(name: users.name.eq('Alice'));
      expect(rows.length, 1);
      expect(rows[0].name, 'Alice');
      expect(rows[0].age, 30);
    });

    test('select().where() with gt', () async {
      final rows = await db.users.select().where(age: users.age.gt(25));
      expect(rows.length, 1);
      expect(rows[0].name, 'Alice');
    });

    test('select().where() with lt', () async {
      final rows = await db.users.select().where(age: users.age.lt(30));
      expect(rows.length, 1);
      expect(rows[0].name, 'Bob');
    });

    test('select().where() with gte', () async {
      final rows = await db.users.select().where(age: users.age.gte(25));
      expect(rows.length, 2);
    });

    test('select().where() with lte', () async {
      final rows = await db.users.select().where(age: users.age.lte(30));
      expect(rows.length, 2);
    });

    test('select().where() with multiple conditions', () async {
      final rows = await db.users
          .select()
          .where(age: users.age.gt(20))
          .where(active: users.active.eq(1));
      expect(rows.length, 1);
      expect(rows[0].name, 'Alice');
    });

    test('select().limit()', () async {
      final rows = await db.users.select().limit(2);
      expect(rows.length, 2);
    });

    test('select().offset()', () async {
      final rows = await db.users.select().limit(10).offset(1);
      expect(rows.length, 2);
    });

    test('select() handles NULL values', () async {
      final rows = await db.users
          .select()
          .where(name: users.name.eq('Charlie'));
      expect(rows[0].age, isNull);
    });

    test('select() returns empty list when no match', () async {
      final rows = await db.users
          .select()
          .where(name: users.name.eq('NonExistent'));
      expect(rows, isEmpty);
    });
  });

  group('INSERT', () {
    test('insert().values() inserts a row', () async {
      await db.users.insert().values(
        id: '44444444-4444-4444-4444-444444444444',
        name: 'Dave',
        age: 40,
        active: 1,
        createdAt: DateTime(2024, 1, 4, 10, 0, 0),
      );

      final rows = await db.users.select().where(name: users.name.eq('Dave'));
      expect(rows.length, 1);
      expect(rows[0].age, 40);
    });

    test('insert().values() with NULL', () async {
      await db.users.insert().values(
        id: '55555555-5555-5555-5555-555555555555',
        name: 'Eve',
        age: null,
        active: 1,
        createdAt: DateTime(2024, 1, 5, 10, 0, 0),
      );

      final rows = await db.users.select().where(name: users.name.eq('Eve'));
      expect(rows[0].age, isNull);
    });

    test('insert().values() throws on missing required field', () async {
      // The InsertBuilder.execute() checks for required fields
      final builder = db.users.insert();
      // Not calling .values() means fields are null
      expect(() => builder.execute(), throwsA(isA<StateError>()));
    });
  });

  group('UPDATE', () {
    test('update().set().where() updates rows', () async {
      await db.users.update().set(age: 99).where(name: users.name.eq('Alice'));

      final rows = await db.users.select().where(name: users.name.eq('Alice'));
      expect(rows[0].age, 99);
    });

    test('update().set() with multiple fields', () async {
      await db.users
          .update()
          .set(name: 'Alice Updated', age: 100)
          .where(name: users.name.eq('Alice'));

      final rows = await db.users
          .select()
          .where(name: users.name.eq('Alice Updated'));
      expect(rows.length, 1);
      expect(rows[0].age, 100);
    });

    test('update() without where() updates all rows', () async {
      await db.users.update().set(active: 0);

      final rows = await db.users.select().where(active: users.active.eq(1));
      expect(rows, isEmpty);
    });

    test('update().set() throws when no fields provided', () async {
      expect(
        () => db.users
            .update()
            .where(name: users.name.eq('Alice'))
            .execute(),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('DELETE', () {
    test('delete().where() deletes matching rows', () async {
      // Charlie has no FK references, safe to delete
      await db.users.delete().where(name: users.name.eq('Charlie'));

      final rows = await db.users.select().where(name: users.name.eq('Charlie'));
      expect(rows, isEmpty);
    });

    test('delete() without where() deletes all rows', () async {
      // First delete dependent rows
      await db.posts.delete();
      await db.users.delete();

      final rows = await db.users.select();
      expect(rows, isEmpty);
    });
  });

  group('Relations - withXxx()', () {
    test('posts.select().withUser() joins user', () async {
      final rows = await db.posts.select().withUser();

      expect(rows.length, 2);
      // Find Alice's post
      final alicePost = rows.firstWhere(
        (r) => r.user.name == 'Alice',
      );
      expect(alicePost.post.title, 'First Post');
      expect(alicePost.user.age, 30);
    });

    test('posts.select().withUser().where() filters correctly', () async {
      final rows = await db.posts
          .select()
          .withUser()
          .where(title: posts.title.eq('First Post'));

      expect(rows.length, 1);
      expect(rows[0].user.name, 'Alice');
    });

    test('nullable FK returns null when no match (LEFT JOIN)', () async {
      // Insert article without author
      await db.articles.insert().values(
        id: 'cccccccc-cccc-cccc-cccc-cccccccccccc',
        title: 'Orphan Article',
        authorId: null,
        createdAt: DateTime(2024, 1, 20, 10, 0, 0),
      );

      // Use title instead of id to avoid ambiguous column reference
      // (both articles and users have 'id' column)
      final rows = await db.articles.select().withAuthor().where(
        title: articles.title.eq('Orphan Article'),
      );

      expect(rows.length, 1);
      expect(rows[0].article.title, 'Orphan Article');
      expect(rows[0].author, isNull);
    });

    test('nullable FK returns user when match exists (LEFT JOIN)', () async {
      // Insert article with author
      await db.articles.insert().values(
        id: 'dddddddd-dddd-dddd-dddd-dddddddddddd',
        title: 'Authored Article',
        authorId: '11111111-1111-1111-1111-111111111111', // Alice
        createdAt: DateTime(2024, 1, 21, 10, 0, 0),
      );

      // Use title instead of id to avoid ambiguous column reference
      final rows = await db.articles.select().withAuthor().where(
        title: articles.title.eq('Authored Article'),
      );

      expect(rows.length, 1);
      expect(rows[0].article.title, 'Authored Article');
      expect(rows[0].author, isNotNull);
      expect(rows[0].author!.name, 'Alice');
    });

    test('multiple withXxx() joins multiple tables', () async {
      // Insert a comment
      await db.comments.insert().values(
        id: 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
        content: 'Great post!',
        postId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', // First Post
        userId: '22222222-2222-2222-2222-222222222222', // Bob
        createdAt: DateTime(2024, 1, 25, 10, 0, 0),
      );

      final rows = await db.comments.select().withPost().withUser();

      expect(rows.length, 1);
      expect(rows[0].comment.content, 'Great post!');
      expect(rows[0].post.title, 'First Post');
      expect(rows[0].user.name, 'Bob');
    });

    test('withPost() then withUser() chain works', () async {
      // Insert a comment
      await db.comments.insert().values(
        id: 'ffffffff-ffff-ffff-ffff-ffffffffffff',
        content: 'Another comment',
        postId: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', // Second Post
        userId: '11111111-1111-1111-1111-111111111111', // Alice
        createdAt: DateTime(2024, 1, 26, 10, 0, 0),
      );

      // withPost() returns CommentsWithPostSelectBuilder
      // which has withUser() method
      final rows = await db.comments.select().withPost().withUser();

      final aliceComment = rows.firstWhere((r) => r.user.name == 'Alice');
      expect(aliceComment.comment.content, 'Another comment');
      expect(aliceComment.post.title, 'Second Post');
    });
  });

  group('Transaction', () {
    test('transaction commits on success', () async {
      await db.transaction((tx) async {
        await tx.users.insert().values(
          id: '66666666-6666-6666-6666-666666666666',
          name: 'TxUser',
          age: 50,
          active: 1,
          createdAt: DateTime(2024, 1, 30, 10, 0, 0),
        );
        await tx.users
            .update()
            .set(age: 51)
            .where(name: users.name.eq('TxUser'));
      });

      final rows = await db.users.select().where(name: users.name.eq('TxUser'));
      expect(rows.length, 1);
      expect(rows[0].age, 51);
    });

    test('transaction rolls back on error', () async {
      try {
        await db.transaction((tx) async {
          await tx.users.insert().values(
            id: '77777777-7777-7777-7777-777777777777',
            name: 'RollbackUser',
            age: 60,
            active: 1,
            createdAt: DateTime(2024, 1, 31, 10, 0, 0),
          );
          throw Exception('Force rollback');
        });
      } catch (_) {
        // Expected
      }

      final rows = await db.users
          .select()
          .where(name: users.name.eq('RollbackUser'));
      expect(rows, isEmpty);
    });

    test('transaction can use multiple table builders', () async {
      await db.transaction((tx) async {
        await tx.users.insert().values(
          id: '88888888-8888-8888-8888-888888888888',
          name: 'MultiTableUser',
          age: 35,
          active: 1,
          createdAt: DateTime(2024, 2, 1, 10, 0, 0),
        );

        await tx.posts.insert().values(
          id: '99999999-9999-9999-9999-999999999999',
          title: 'Multi Table Post',
          content: 'Content in transaction',
          userId: '88888888-8888-8888-8888-888888888888',
          createdAt: DateTime(2024, 2, 1, 11, 0, 0),
        );
      });

      final userRows = await db.users
          .select()
          .where(name: users.name.eq('MultiTableUser'));
      expect(userRows.length, 1);

      final postRows = await db.posts
          .select()
          .where(title: posts.title.eq('Multi Table Post'));
      expect(postRows.length, 1);
      expect(postRows[0].userId, '88888888-8888-8888-8888-888888888888');
    });
  });
}
