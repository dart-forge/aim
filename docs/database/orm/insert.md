---
title: INSERT - Aim ORM
description: Insert data with type-safe INSERT operations.
head:
  - - meta
    - name: keywords
      content: Dart ORM insert, database insert, type-safe insert
---

# INSERT

Insert data with type-safe INSERT operations.

## Basic Insert

Use `.insert().values()` to insert a row:

```dart
await db.users.insert().values(
  id: 'uuid-here',
  name: 'Alice',
  email: 'alice@example.com',
  createdAt: DateTime.now(),
);
```

## Values Parameters

The `.values()` method takes named parameters matching the table schema.
Non-nullable fields are marked as `required`, while nullable fields can be omitted:

```dart
// Required fields must be provided
// Nullable fields (age, gender) can be omitted
await db.users.insert().values(
  id: 'user-123',
  name: 'Bob',
  email: 'bob@example.com',
  createdAt: DateTime.now(),
  // age: 25,      // optional - nullable field
  // gender: 'M',  // optional - nullable field
);
```

## Return Value

INSERT returns `Future<int>` - the number of affected rows:

```dart
final affected = await db.users.insert().values(
  id: 'user-456',
  name: 'Charlie',
  email: 'charlie@example.com',
  createdAt: DateTime.now(),
);

print('Inserted $affected row(s)');  // Inserted 1 row(s)
```

## Examples

### Insert User

```dart
Future<void> createUser({
  required String id,
  required String name,
  required String email,
}) async {
  await db.users.insert().values(
    id: id,
    name: name,
    email: email,
    createdAt: DateTime.now(),
  );
}
```

### Insert Post

```dart
Future<void> createPost({
  required String userId,
  required String title,
  required String content,
}) async {
  await db.posts.insert().values(
    userId: userId,
    title: title,
    content: content,
    createdAt: DateTime.now(),
  );
}
```

### Columns the Database Fills

A `serial()` column, and a `NOT NULL` column with a default, can be left out
of `values()`. The statement then writes `DEFAULT` in that position and the
database fills it: a serial column takes the next value of its sequence, a
defaulted column takes its default.

```dart
@PgTable('posts')
final posts = (
  id: serial('id').primaryKey(),
  status: varchar('status', length: 20).withDefault('draft'),
  title: varchar('title', length: 255),
);

await db.posts.insert().values(title: 'Hello');
// INSERT INTO posts (id, status, title) VALUES (DEFAULT, DEFAULT, :title)
```

Passing a value still works and is used as given.

A nullable column is not treated this way: leaving it out sends an explicit
`NULL`, as before. An optional parameter cannot tell "not given" from "NULL
wanted", so a nullable column with a default has to be given its value to
receive the default.

`.values()` also returns `Future<int>` (the affected row count), never the
generated id — there is no builder method that reads it back. If you need
the id, use `db.query()` (not `db.execute()`) with `RETURNING` instead, since
`query()` is the method that returns rows:

```dart
final rows = await db.query(
  'INSERT INTO posts (user_id, title, content, created_at) '
  'VALUES (:userId, :title, :content, :createdAt) '
  'RETURNING id',
  params: {
    'userId': userId,
    'title': title,
    'content': content,
    'createdAt': DateTime.now(),
  },
);
final insertedId = rows.first['id'];
```

## Next Steps

- [UPDATE](/database/orm/update) - Update data
- [DELETE](/database/orm/delete) - Delete data
- [Transactions](/database/orm/transactions) - Atomic operations
- [SELECT](/database/orm/select) - Query data