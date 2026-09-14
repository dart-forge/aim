/// PostgreSQL database driver for the Aim ORM framework.
///
/// This library provides PostgreSQL-specific implementations of the Aim ORM
/// abstractions. It includes support for:
///
/// - Connection pooling with configurable limits, health checks and eviction
/// - SSL/TLS connections with multiple security modes
/// - Cleartext, MD5 and SCRAM-SHA-256 password authentication
/// - Simple and Extended Query protocols
/// - Parameter binding and prepared statements
///
/// ## Usage
///
/// ```dart
/// import 'package:aim_postgres/aim_postgres.dart';
///
/// final db = await PostgresDatabase.connect(
///   'postgresql://user:pass@localhost:5432/mydb',
///   maxConnections: 20,
/// );
///
/// final results = await db.query('SELECT * FROM users WHERE id = $1', args: [1]);
/// print(db.poolStats);
/// await db.close();
/// ```
///
/// For SSL/TLS connections:
///
/// ```dart
/// final db = await PostgresDatabase.connect(
///   'postgresql://user:pass@localhost:5432/mydb?sslmode=require',
/// );
/// ```

library;

export 'src/pg_connection.dart';
export 'src/pg_database.dart';
export 'src/pool/pool.dart' show PoolOptions, PoolStats, PoolTimeoutException;
export 'src/types/query_result_decoder.dart' show PostgresDecodeException;
