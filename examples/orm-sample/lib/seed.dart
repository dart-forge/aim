import 'package:aim_orm/aim_orm.dart';
import 'package:aim_orm_postgres/aim_orm_postgres.dart';
import 'package:aim_postgres/aim_postgres.dart';
import 'package:orm_sample/test.dart';
import 'package:uuid/uuid.dart';

part 'seed.g.dart';

@PgTable('status')
final status = (
  id: uuid('id').primaryKey(),
  description: varchar('description', length: 255),
  createdAt: timestamp('created_at').withDefault(DateTime.now()),
);

void main() async {
  final db = await PostgresDatabase.connect(
    'postgres://test:test@localhost:5432/test_db',
  );

  final result = await db.query('SELECT COUNT(*) from users;');
  int count = result[0]['count'] as int;
  if (count == 0) {
    await db.transaction((tx) async {
      for (var i = 0; i < 100; i++) {
        await tx.users.insert().values(
          id: Uuid().v4(),
          name: 'test$count',
          email: 'test$count@example.com',
          createdAt: DateTime.now(),
        );
        count++;
      }
    });
  }


  final users = await db.users.select().limit(1).then((value) => value.first);

  final postsCount = await db.query('SELECT COUNT(*) from posts;');
  int postCount = postsCount[0]['count'] as int;
  if (postCount == 0) {
    await db.transaction((tx) async {
      for (var i = 0; i < 100; i++) {
        await tx.posts.insert().values(
          id: Uuid().v4(),
          userId: users.id,
          title: 'Post Title $i',
          content: 'This is the content of post number $i.',
          createdAt: DateTime.now(),
          statusId: Uuid().v4(),
        );
      }
    });
  }

  final postsWithUsers = await db.posts.select().withUser();
  for (var (:post, :user) in postsWithUsers) {
    print('${post.id} ${post.title}, Author: ${user.name}');
  }

  await db.close();
}
