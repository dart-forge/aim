/// Holds this generator's idea of a column's Dart type against the type the
/// column actually carries.
///
/// A column's value type lives on the column classes in `aim_orm` and
/// `aim_orm_postgres`: it is the `T` of `Column<T, Self>`, and it decides
/// what `eq`, `gt`, `lt` and `withDefault` take. This generator repeats that
/// type as a string, in two places, so the code it writes can name it.
///
/// Nothing used to compare the two. A serial column was declared
/// `Column<String, SerialColumn>` while both tables here said `int`, and
/// every suite passed: the golden fixtures asserted the generated `int`, and
/// the column's own tests looked at its name, its flags and its SQL but
/// never at its value type. The contradiction sat between two packages that
/// no test crossed.
///
/// These tests cross it. The value type is read from the column itself
/// rather than written down again, so a change on either side of the
/// boundary shows up here.
library;

import 'package:aim_orm/aim_orm.dart';
import 'package:aim_orm_codegen/src/record_table_generator.dart';
import 'package:aim_orm_codegen/src/table_collector_builder.dart';
import 'package:aim_orm_postgres/aim_orm_postgres.dart';
import 'package:test/test.dart';

/// The value type [column] carries, named the way generated code names it.
///
/// `T` is inferred from the column's own type parameter at the call site, so
/// this reports what the column class declares instead of repeating it. Keep
/// the calls inline: assigning a column to a variable of a wider type first
/// would erase the very thing being read.
String valueTypeOf<T>(Column<T, dynamic> column) => T.toString();

void main() {
  /// Every column builder, paired with the value type its column carries.
  final carried = <String, String>{
    'integer': valueTypeOf(integer('c')),
    'varchar': valueTypeOf(varchar('c')),
    'text': valueTypeOf(text('c')),
    'timestamp': valueTypeOf(timestamp('c')),
    'serial': valueTypeOf(serial('c')),
    'uuid': valueTypeOf(uuid('c')),
    // The generator writes `Map<String, dynamic>` for a jsonb column
    // whatever type argument the schema gave it, so that is the shape to
    // hold it to.
    'jsonb': valueTypeOf(jsonb<Map<String, dynamic>>('c')),
  };

  group('the collected column table', () {
    for (final entry in carried.entries) {
      test('${entry.key}() is collected as ${entry.value}', () {
        final collected = columnTypesByBuilder[entry.key];
        expect(
          collected,
          isNotNull,
          reason:
              '${entry.key}() exists as a column builder but this generator '
              'does not know it, so a schema using it generates nothing for '
              'that column',
        );
        expect(
          collected!['dartType'],
          equals(entry.value),
          reason:
              'a ${entry.key}() column carries ${entry.value}, so generated '
              'code naming any other type does not describe the value that '
              'arrives',
        );
      });
    }

    test('covers exactly the builders checked here', () {
      expect(
        columnTypesByBuilder.keys.toSet(),
        equals(carried.keys.toSet()),
        reason:
            'a builder added to the generator without a line in this test '
            'goes back to having nothing compare its type against the '
            'column class',
      );
    });
  });

  group('the generated-code column mapper', () {
    /// The mapper's `unknown` entry is a fallback for a column this
    /// generator could not read, not a builder anyone writes.
    final mapped = PgColumnMapper.values.where(
      (mapper) => mapper != PgColumnMapper.unknown,
    );

    for (final entry in carried.entries) {
      test('${entry.key} is written as ${entry.value}', () {
        final mapper = mapped.where((m) => m.name == entry.key);
        expect(
          mapper,
          hasLength(1),
          reason:
              'the mapper has no entry named ${entry.key}, so generated code '
              'falls back to dynamic for a column that has a type',
        );
        expect(mapper.single.dartType, equals(entry.value));
      });
    }

    test('maps exactly the builders checked here', () {
      expect(
        mapped.map((mapper) => mapper.name).toSet(),
        equals(carried.keys.toSet()),
      );
    });

    test('agrees with the collected column table', () {
      expect(
        {for (final mapper in mapped) mapper.name: mapper.dartType},
        equals({
          for (final entry in columnTypesByBuilder.entries)
            entry.key: entry.value['dartType'],
        }),
        reason:
            'the two tables are read at different stages of the build, so a '
            'column would be collected as one type and written as another',
      );
    });
  });
}
