import 'package:aim_sqlite/aim_sqlite.dart';
import 'package:test/test.dart';

void main() {
  group('the library loading failures', () {
    test('are two types, so a catch can tell them apart', () {
      // One says there is no libsqlite3 here; the other says there is one
      // and it is too old. A caller does different things about those --
      // install a library, or upgrade the one it has -- so neither may be
      // catchable as the other. Asserted because making one extend the
      // other is the obvious tidying-up that would break it.
      final tooOld = SqliteLibraryTooOldException(
        path: 'libsqlite3.dylib',
        version: 3007017,
        requiredVersion: 3008007,
      );
      final notFound = SqliteLibraryNotFoundException([
        'libsqlite3.dylib',
      ], 'dlopen failed');

      expect(tooOld, isNot(isA<SqliteLibraryNotFoundException>()));
      expect(notFound, isNot(isA<SqliteLibraryTooOldException>()));
    });

    test('say in words what went wrong and where', () {
      // These two reach a caller from inside a worker isolate, where a log
      // line is often all there is to go on, so toString has to carry the
      // paths that were tried and the versions that did not match.
      expect(
        SqliteLibraryNotFoundException([
          'libsqlite3.so.0',
          'libsqlite3.so',
        ], 'dlopen failed').toString(),
        allOf(
          contains('libsqlite3.so.0'),
          contains('libsqlite3.so'),
          contains('dlopen failed'),
        ),
      );
      expect(
        SqliteLibraryTooOldException(
          path: '/usr/lib/libsqlite3.dylib',
          version: 3007017,
          requiredVersion: 3008007,
        ).toString(),
        allOf(
          contains('/usr/lib/libsqlite3.dylib'),
          contains('3007017'),
          contains('3008007'),
        ),
      );
    });
  });
}
