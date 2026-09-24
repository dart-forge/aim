---
title: Transactions - Aim ORM
description: Use transactions for atomic database operations with automatic rollback on errors.
head:
  - - meta
    - name: keywords
      content: Dart ORM transactions, database transactions, atomic operations
---

# Transactions

Use transactions for atomic database operations with automatic rollback on errors.

## Basic Usage

Use `db.transaction()` to execute multiple operations atomically. Inside the
callback, every generated table (`tx.users`, `tx.posts`, ...) is available on
the `tx` (`PostgresTransaction`) object, and `.insert().values()` takes named
parameters matching the table's columns — not a record literal:

```dart
import 'package:uuid/uuid.dart';

await db.transaction((tx) async {
  final userId = const Uuid().v4();

  await tx.users.insert().values(
    id: userId,
    name: 'Alice',
    email: 'alice@example.com',
    createdAt: DateTime.now(),
  );

  await tx.posts.insert().values(
    id: const Uuid().v4(),
    userId: userId,
    title: 'My First Post',
    content: 'Hello, World!',
    createdAt: DateTime.now(),
  );
});
```

::: warning `serial()` primary keys
If a table's primary key is `serial()` instead of `uuid()`, the generated
`values()` still requires it as a named parameter — it is not omitted the
way a hand-written `INSERT` could leave it out for the sequence to fill in.
Passing a literal like `0` inserts that literal, which fails on the second
row. See the [INSERT guide](/database/orm/insert#serial-columns) for the raw-SQL
workaround.
:::

## Automatic Rollback

If any operation fails, the entire transaction is automatically rolled back:

```dart
try {
  await db.transaction((tx) async {
    final userId = const Uuid().v4();

    await tx.users.insert().values(
      id: userId,
      name: 'Alice',
      email: 'alice@example.com',
      createdAt: DateTime.now(),
    );

    // If this fails, the user insert above is also rolled back
    await tx.posts.insert().values(
      id: const Uuid().v4(),
      userId: userId,
      title: 'Post',
      content: 'Content',
      createdAt: DateTime.now(),
    );
  });
} catch (e) {
  print('Transaction failed: $e');
  // Both inserts are rolled back
}
```

## Transaction Context

Inside a transaction callback, use `tx` instead of `db`:

```dart
await db.transaction((tx) async {
  // Use tx.users, not db.users
  final matches = await tx.users.select().where(id: users.id.eq('user-123'));

  await tx.users
      .update()
      .set(name: 'Updated')
      .where(id: users.id.eq('user-123'));
});
```

## Return Values

Transactions can return values:

```dart
final newUserId = await db.transaction((tx) async {
  final userId = const Uuid().v4();

  await tx.users.insert().values(
    id: userId,
    name: 'Alice',
    email: 'alice@example.com',
    createdAt: DateTime.now(),
  );

  return userId;
});

final created = await db.users.select().where(id: users.id.eq(newUserId));
print(created.first.name);  // Alice
```

## Examples

### Transfer Operation

`.set()` assigns literal values, not SQL expressions, so a balance update
has to read the current value inside the same transaction first:

```dart
Future<void> transfer({
  required String fromUserId,
  required String toUserId,
  required int amount,
}) async {
  await db.transaction((tx) async {
    final sender = (await tx.accounts
            .select()
            .where(userId: accounts.userId.eq(fromUserId)))
        .first;
    final receiver = (await tx.accounts
            .select()
            .where(userId: accounts.userId.eq(toUserId)))
        .first;

    // Deduct from sender
    await tx.accounts
        .update()
        .set(balance: sender.balance - amount)
        .where(userId: accounts.userId.eq(fromUserId));

    // Add to receiver
    await tx.accounts
        .update()
        .set(balance: receiver.balance + amount)
        .where(userId: accounts.userId.eq(toUserId));
  });
}
```

This reads both balances before writing either, so it is only safe against
concurrent transfers if the underlying row locking (or a `WHERE balance >=
amount` guard checked against the result) prevents an overdraft — the ORM
does not add that guarantee for you.

### Create User with Profile

```dart
Future<void> createUserWithProfile({
  required String id,
  required String name,
  required String email,
  required String bio,
}) async {
  await db.transaction((tx) async {
    await tx.users.insert().values(
      id: id,
      name: name,
      email: email,
      createdAt: DateTime.now(),
    );

    await tx.profiles.insert().values(
      id: const Uuid().v4(),
      userId: id,
      bio: bio,
      createdAt: DateTime.now(),
    );
  });
}
```

### Bulk Insert

```dart
Future<void> bulkInsertUsers(List<Map<String, dynamic>> userData) async {
  await db.transaction((tx) async {
    for (final data in userData) {
      await tx.users.insert().values(
        id: data['id'] as String,
        name: data['name'] as String,
        email: data['email'] as String,
        createdAt: DateTime.now(),
      );
    }
  });
}
```

## Next Steps

- [SELECT](/database/orm/select) - Query data
- [INSERT](/database/orm/insert) - Insert data
- [UPDATE](/database/orm/update) - Update data
- [DELETE](/database/orm/delete) - Delete data
