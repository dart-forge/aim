import 'package:aim_orm/src/query_builder/condition.dart';

/// Abstract base class for all column types.
///
/// [T] is the Dart type that this column maps to.
/// [Self] is the concrete column type for fluent method chaining.
///
/// ## Example
///
/// ```dart
/// final id = integer('id').primaryKey();
/// final name = varchar('name', length: 100).unique();
/// final age = integer('age').nullable();
/// ```
abstract class Column<T, Self> {
  /// The name of the column in the database.
  final String name;

  /// Whether the column allows null values.
  final bool isNullable;

  /// Whether the column is a primary key.
  final bool isPrimaryKey;

  /// Whether the column has a unique constraint.
  final bool isUnique;

  /// The default value for the column.
  final T? defaultValue;

  /// Creates a new column with the given properties.
  const Column({
    required this.name,
    this.isNullable = false,
    this.isPrimaryKey = false,
    this.isUnique = false,
    this.defaultValue,
  });

  /// Creates a copy of this column with the given properties overridden.
  Self copyWith({
    bool? isPrimaryKey,
    bool? isNullable,
    bool? isUnique,
    T? defaultValue,
  });

  /// Returns the SQL type representation of this column.
  String toSql();

  /// Marks this column as a primary key.
  Self primaryKey() => copyWith(isPrimaryKey: true);

  /// Adds a unique constraint to this column.
  Self unique() => copyWith(isUnique: true);

  /// Marks this column as nullable.
  Self nullable() => copyWith(isNullable: true);

  /// Sets a default value for this column.
  Self withDefault(T value) => copyWith(defaultValue: value);

  /// Creates an equality condition (column = value).
  Condition eq(T value) => Condition(name, ConditionOperator.equal, value);

  /// Creates a greater-than condition (column > value).
  Condition gt(T value) =>
      Condition(name, ConditionOperator.greaterThan, value);

  /// Creates a less-than condition (column < value).
  Condition lt(T value) => Condition(name, ConditionOperator.lessThan, value);

  /// Creates a greater-than-or-equal condition (column >= value).
  Condition gte(T value) =>
      Condition(name, ConditionOperator.greaterThanOrEqual, value);

  /// Creates a less-than-or-equal condition (column <= value).
  Condition lte(T value) =>
      Condition(name, ConditionOperator.lessThanOrEqual, value);

  /// Creates an IN condition (column IN (values)).
  Condition inList(List<T> values) =>
      Condition(name, ConditionOperator.inList, values);

  /// Marks this column as indexed.
  Self indexed() => copyWith();

  /// Defines a foreign key reference to another column.
  ///
  /// [target] is a function that returns the referenced column.
  /// [onDelete] specifies the action when the referenced row is deleted.
  /// [onUpdate] specifies the action when the referenced row is updated.
  Self references<R>(
    Column<T, R> Function() target, {
    OnDeleteAction? onDelete,
    OnUpdateAction? onUpdate,
  }) => copyWith();
}

/// Action to take when a referenced row is deleted.
enum OnDeleteAction {
  /// Delete the referencing rows.
  cascade('CASCADE'),

  /// Set the foreign key column to null.
  setNull('SET NULL'),

  /// Prevent deletion if references exist.
  restrict('RESTRICT'),

  /// Set the foreign key column to its default value.
  setDefault('SET DEFAULT');

  /// The SQL keyword for this action.
  final String sqlKeyword;

  const OnDeleteAction(this.sqlKeyword);
}

/// Action to take when a referenced row is updated.
enum OnUpdateAction {
  /// Update the foreign key in referencing rows.
  cascade('CASCADE'),

  /// Set the foreign key column to null.
  setNull('SET NULL'),

  /// Prevent update if references exist.
  restrict('RESTRICT'),

  /// Set the foreign key column to its default value.
  setDefault('SET DEFAULT');

  /// The SQL keyword for this action.
  final String sqlKeyword;

  const OnUpdateAction(this.sqlKeyword);
}

/// A column that stores integer values.
///
/// Maps to INTEGER in SQL.
class IntegerColumn extends Column<int, IntegerColumn> {
  /// Creates a new integer column with the given [name].
  const IntegerColumn({
    required super.name,
    super.isPrimaryKey,
    super.isNullable,
    super.isUnique,
    super.defaultValue,
  });

  @override
  IntegerColumn copyWith({
    bool? isPrimaryKey,
    bool? isNullable,
    bool? isUnique,
    int? defaultValue,
  }) => IntegerColumn(
    name: name,
    isPrimaryKey: isPrimaryKey ?? this.isPrimaryKey,
    isNullable: isNullable ?? this.isNullable,
    isUnique: isUnique ?? this.isUnique,
    defaultValue: defaultValue ?? this.defaultValue,
  );

  @override
  String toSql() => 'INTEGER';
}

/// A column that stores variable-length character strings.
///
/// Maps to VARCHAR(length) in SQL.
class VarcharColumn extends Column<String, VarcharColumn> {
  /// The maximum length of the string.
  final int? length;

  /// Creates a new varchar column with the given [name] and optional [length].
  const VarcharColumn({
    required super.name,
    this.length,
    super.isPrimaryKey,
    super.isNullable,
    super.isUnique,
    super.defaultValue,
  });

  @override
  VarcharColumn copyWith({
    bool? isPrimaryKey,
    bool? isNullable,
    bool? isUnique,
    String? defaultValue,
    int? length,
  }) => VarcharColumn(
    name: name,
    length: length ?? this.length,
    isPrimaryKey: isPrimaryKey ?? this.isPrimaryKey,
    isNullable: isNullable ?? this.isNullable,
    isUnique: isUnique ?? this.isUnique,
    defaultValue: defaultValue ?? this.defaultValue,
  );

  @override
  String toSql() => length == null ? 'VARCHAR' : 'VARCHAR($length)';
}

/// A column that stores text of unlimited length.
///
/// Maps to TEXT in SQL.
class TextColumn extends Column<String, TextColumn> {
  /// Creates a new text column with the given [name].
  const TextColumn({
    required super.name,
    super.isPrimaryKey,
    super.isNullable,
    super.isUnique,
    super.defaultValue,
  });

  @override
  TextColumn copyWith({
    bool? isPrimaryKey,
    bool? isNullable,
    bool? isUnique,
    String? defaultValue,
  }) => TextColumn(
    name: name,
    isPrimaryKey: isPrimaryKey ?? this.isPrimaryKey,
    isNullable: isNullable ?? this.isNullable,
    isUnique: isUnique ?? this.isUnique,
    defaultValue: defaultValue ?? this.defaultValue,
  );

  @override
  String toSql() => 'TEXT';
}

/// A column that stores date and time values.
///
/// Maps to TIMESTAMP in SQL.
class TimestampColumn extends Column<DateTime, TimestampColumn> {
  /// Whether the default value is CURRENT_TIMESTAMP.
  final bool defaultNow;

  /// Creates a new timestamp column with the given [name].
  const TimestampColumn({
    required super.name,
    this.defaultNow = false,
    super.isPrimaryKey,
    super.isNullable,
    super.isUnique,
    super.defaultValue,
  });

  /// Sets the default value to CURRENT_TIMESTAMP.
  TimestampColumn withDefaultNow() => TimestampColumn(
    name: name,
    defaultNow: true,
    isPrimaryKey: isPrimaryKey,
    isNullable: isNullable,
    isUnique: isUnique,
  );

  @override
  TimestampColumn copyWith({
    bool? isPrimaryKey,
    bool? isNullable,
    bool? isUnique,
    DateTime? defaultValue,
  }) => TimestampColumn(
    name: name,
    defaultNow: defaultNow,
    isPrimaryKey: isPrimaryKey ?? this.isPrimaryKey,
    isNullable: isNullable ?? this.isNullable,
    isUnique: isUnique ?? this.isUnique,
    defaultValue: defaultValue ?? this.defaultValue,
  );

  @override
  String toSql() => 'TIMESTAMP';
}
