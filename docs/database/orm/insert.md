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
  required int id,
  required String userId,
  required String title,
  required String content,
}) async {
  await db.posts.insert().values(
    id: id,
    userId: userId,
    title: title,
    content: content,
    createdAt: DateTime.now(),
  );
}
```

### Serial Columns

::: warning
A `serial()` column is not left out of the statement the builder writes: the
generated `values()` takes it like any other column and the `INSERT` names
it. Passing `0` inserts a literal zero, and the second row to do so fails on
the primary key. To let the sequence assign the value, write the statement
yourself and leave the column out:

```dart
await db.execute(
  'INSERT INTO posts (user_id, title, content, created_at) '
  'VALUES (:userId, :title, :content, :createdAt)',
  params: {
    'userId': userId,
    'title': title,
    'content': content,
    'createdAt': DateTime.now(),
  },
);
```

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
:::

## Next Steps

- [UPDATE](/database/orm/update) - Update data
- [DELETE](/database/orm/delete) - Delete data
- [Transactions](/database/orm/transactions) - Atomic operations
- [SELECT](/database/orm/select) - Query data