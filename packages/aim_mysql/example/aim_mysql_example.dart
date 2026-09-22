// Exercises aim_mysql's query, execute, insert and transaction API against
// a real MySQL 8.0 or 8.4 server.
//
// Point AIM_MYSQL_URL at a server and run:
//
//   export AIM_MYSQL_URL="mysql://user:password@localhost:3306/mydb"
//   dart run example/aim_mysql_example.dart
import 'dart:io';

import 'package:aim_mysql/aim_mysql.dart';

Future<void> main() async {
  final url = Platform.environment['AIM_MYSQL_URL'];
  if (url == null) {
    print('''
Set AIM_MYSQL_URL to a MySQL connection string and run this example again:

  export AIM_MYSQL_URL="mysql://user:password@localhost:3306/mydb"
  dart run example/aim_mysql_example.dart
''');
    return;
  }

  final db = await MySqlDatabase.connect(url);
  try {
    await _basicQueries(db);
    await _transactions(db);
  } finally {
    await db.close();
  }
}

Future<void> _basicQueries(MySqlDatabase db) async {
  await db.execute('DROP TABLE IF EXISTS aim_mysql_example_users');
  await db.execute('''
    CREATE TABLE aim_mysql_example_users (
      id INT AUTO_INCREMENT PRIMARY KEY,
      name VARCHAR(100) NOT NULL,
      email VARCHAR(255) NOT NULL
    )
  ''');

  // insert() is how the id an INSERT generated is read back -- see the
  // README's note on SELECT LAST_INSERT_ID() for why that call, rather
  // than query(), is the right tool for this.
  final aliceId = await db.insert(
    'INSERT INTO aim_mysql_example_users (name, email) '
    'VALUES (:name, :email)',
    params: {'name': 'Alice', 'email': 'alice@example.com'},
  );
  print('Inserted Alice with id $aliceId');

  final allUsers = await db.query('SELECT * FROM aim_mysql_example_users');
  print('All users: $allUsers');

  // Positional (?) parameters work the same as named (:name) ones; a
  // single statement uses one style or the other, never both.
  final byId = await db.query(
    'SELECT * FROM aim_mysql_example_users WHERE id = ?',
    args: [aliceId],
  );
  print('Looked up by id: $byId');
}

Future<void> _transactions(MySqlDatabase db) async {
  try {
    await db.transaction((tx) async {
      await tx.execute(
        'INSERT INTO aim_mysql_example_users (name, email) '
        'VALUES (:name, :email)',
        params: {'name': 'Bob', 'email': 'bob@example.com'},
      );
      throw Exception('simulated failure to show a rollback');
    });
  } catch (e) {
    print('Transaction rolled back: $e');
  }

  final afterRollback = await db.query('SELECT * FROM aim_mysql_example_users');
  print('Users after rollback (Bob should be absent): $afterRollback');

  await db.execute('DROP TABLE aim_mysql_example_users');
}
