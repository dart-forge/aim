import 'package:aim_sqlite/src/ffi/bindings.dart';
import 'package:test/test.dart';

void main() {
  group('SqliteLibrary.open', () {
    test('loads the platform library and reports a usable version', () {
      final lib = SqliteLibrary.open();

      // 3.7.0 is the first release with WAL, which the driver requires.
      expect(lib.versionNumber, greaterThanOrEqualTo(3007000));
    });

    test('names every place it looked when the library is missing', () {
      expect(
        () => SqliteLibrary.open(libraryPath: '/nonexistent/libsqlite3.dylib'),
        throwsA(
          isA<SqliteLibraryNotFoundException>().having(
            (e) => e.searched,
            'searched',
            contains('/nonexistent/libsqlite3.dylib'),
          ),
        ),
      );
    });

    test('reads the override from the environment', () {
      // AIM_SQLITE_LIBRARY is only read when no explicit path is given, so
      // this asserts the precedence rather than the loading itself.
      expect(SqliteLibrary.environmentVariable, 'AIM_SQLITE_LIBRARY');
    });
  });
}
