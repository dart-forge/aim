import 'package:aim_orm/aim_orm.dart';

/// Annotation for marking a class as a PostgreSQL database table.
///
/// This is a PostgreSQL-specific extension of [Table] that should be used
/// when defining tables for PostgreSQL databases.
///
/// ## Example
///
/// The annotation goes on a top-level variable holding a record, one field
/// per column. That is the only shape the code generator and `aim
/// db:generate` read.
///
/// ```dart
/// @PgTable('users')
/// final users = (
///   id: serial('id').primaryKey(),
///   name: varchar('name', length: 100),
///   email: varchar('email', length: 255).unique(),
///   createdAt: timestamp('created_at').withDefaultNow(),
/// );
/// ```
///
/// Use with [aim_orm_codegen](https://pub.dev/packages/aim_orm_codegen) to
/// generate type-safe query builders.
class PgTable extends Table {
  /// Creates a new [PgTable] annotation with the given table [name].
  const PgTable(super.name);
}
