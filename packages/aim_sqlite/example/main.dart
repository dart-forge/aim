// Run this with `dart run example/main.dart`. It creates its database in a
// throwaway directory and deletes it again, so it leaves nothing behind.
import 'dart:io';

import 'package:aim_sqlite/aim_sqlite.dart';

Future<void> main() async {
  final dir = await Directory.systemTemp.createTemp('aim_sqlite_example');
  final db = await SqliteDatabase.open('${dir.path}/app.db');

  try {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        created_at TIMESTAMP NOT NULL
      )
    ''');

    // RETURNING, rather than last_insert_rowid(): a read goes to one of the
    // read-only connections, which has never inserted anything, so
    // query('SELECT last_insert_rowid()') answers 0 here. It would answer
    // correctly on a database with no readers -- every in-memory one is
    // forced to that -- which is the trap rather than the consolation.
    // Asking the INSERT itself gets the id in every configuration.
    final inserted = await db.query(
      'INSERT INTO users (name, created_at) VALUES (:name, :createdAt) '
      'RETURNING id',
      params: {'name': 'Alice', 'createdAt': DateTime.now().toUtc()},
    );
    final id = inserted.single['id'] as int;
    print('inserted user $id');

    final users = await db.query('SELECT * FROM users');
    for (final user in users) {
      // created_at comes back as a DateTime, in UTC, because the column is
      // declared TIMESTAMP.
      print('${user['id']}: ${user['name']} (${user['created_at']})');
    }

    await db.transaction((tx) async {
      // Through tx, not db: a statement on the database from in here would
      // wait for this very transaction, and is refused instead.
      await tx.execute(
        'UPDATE users SET name = :name WHERE id = :id',
        params: {'name': 'Alice Updated', 'id': id},
      );
    });

    final renamed = await db.query(
      'SELECT name FROM users WHERE id = ?',
      args: [id],
    );
    print('renamed to ${renamed.single['name']}');
  } finally {
    await db.close();
    await dir.delete(recursive: true);
  }
}
