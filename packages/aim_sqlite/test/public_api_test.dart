import 'dart:io';

import 'package:test/test.dart';

/// The public barrel may export the driver, its options, its exceptions and
/// its stats only, and must never make dart:ffi or dart:isolate reachable. A
/// Pointer or a SendPort in the public surface would put a raw handle in the
/// caller's hands.
void main() {
  test('lib/aim_sqlite.dart exports only the allowed surface', () {
    final source = File('lib/aim_sqlite.dart').readAsStringSync();
    final exports =
        RegExp(
              r'''^export\s+['"]([^'"]+)['"](\s+show\s+([^;]+))?;''',
              multiLine: true,
            )
            .allMatches(source)
            .map(
              (m) => (
                uri: m.group(1)!,
                show: m.group(3) == null
                    ? null
                    : _collapseWhitespace(m.group(3)!),
              ),
            )
            .toList();

    expect(exports, hasLength(4));
    expect(exports[0], (
      uri: 'src/sqlite_database.dart',
      show: 'SqliteDatabase',
    ));
    expect(exports[1], (
      uri: 'src/sqlite_options.dart',
      show: 'SqliteOptions, SqliteSynchronous',
    ));
    expect(exports[2], (
      uri: 'src/sqlite_exception.dart',
      show:
          'SqliteException, SqliteDecodeException, SqliteTimeoutException, '
          'SqliteLibraryNotFoundException, SqliteLibraryTooOldException',
    ));
    expect(exports[3], (uri: 'src/sqlite_stats.dart', show: 'SqliteStats'));
  });

  test('no exported file reaches dart:ffi or dart:isolate', () {
    // The file list is DERIVED from the barrel's own exports, not written
    // out again: a hardcoded list lets a newly exported file pass this test
    // simply by never being added to it. isNotEmpty guards the derivation
    // itself -- a barrel that parsed to no exports would otherwise make the
    // loop below, and so the whole test, pass vacuously.
    final exported =
        RegExp(r'''^export\s+['"](src/[^'"]+)['"]''', multiLine: true)
            .allMatches(File('lib/aim_sqlite.dart').readAsStringSync())
            .map((m) => 'lib/${m.group(1)!}')
            .toList();
    expect(exported, isNotEmpty);

    for (final path in exported) {
      final source = File(path).readAsStringSync();
      // Both imports, not only ffi: a file could reach for ReceivePort or
      // Isolate.spawn without ever writing the word SendPort.
      expect(source, isNot(contains("import 'dart:ffi'")), reason: path);
      expect(source, isNot(contains("import 'dart:isolate'")), reason: path);
      expect(source, isNot(contains('Pointer<')), reason: path);
      expect(source, isNot(contains('SendPort')), reason: path);
    }
  });

  test('only the connection layer touches ffi', () {
    // Keeping FFI confined to these two files is what makes the rest unit
    // testable.
    final ffiUsers =
        Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .where((f) => f.readAsStringSync().contains("import 'dart:ffi'"))
            .map((f) => f.path.replaceAll(r'\', '/'))
            .toList()
          ..sort();

    expect(ffiUsers, [
      'lib/src/ffi/bindings.dart',
      'lib/src/worker/connection.dart',
    ]);
  });

  test('the reader pool spawns its handles read-only', () {
    // Source-level only: this checks that ReaderPool.spawn asks for
    // readOnly: true, not that a reader actually refuses a write. The
    // behavioural half of that guarantee is covered elsewhere, by a
    // connection-level test that opens a read-only connection and asserts a
    // write on it fails with result code 8 (SQLITE_READONLY). That test
    // cannot stand in for this one: routing already keeps an ordinary write
    // away from a reader, so flipping this flag would leave every other
    // test green, with the property resting on the driver's own routing
    // check alone instead of on SQLite refusing it as well.
    final source = File('lib/src/reader_pool.dart').readAsStringSync();
    final spawnsReadOnly = RegExp(
      r'SqliteWorkerHandle\.spawn\([^)]*readOnly:\s*true',
    ).hasMatch(source);
    expect(
      spawnsReadOnly,
      isTrue,
      reason:
          'ReaderPool.spawn must open its handles with readOnly: true, or a '
          'misrouted write would reach a "read-only" connection with '
          "nothing but the driver's own check standing in the way",
    );
  });
}

/// Collapses every run of whitespace in [s] to a single space, and trims the
/// ends.
///
/// Load-bearing, now that the exception export shows five names: dart format
/// breaks that `show` clause across an indented line per name, so the
/// captured clause arrives with newlines and indentation inside it. It was
/// not, when the same clause showed three and fitted on one line -- so this
/// is the wrap the comment here used to call hypothetical. Comparing the raw
/// capture would tie this test to exactly where dart format happens to break
/// the line, which is not a property of the public surface. Collapsing
/// whitespace first keeps the comparison about which identifiers are
/// exported, and in what order, and nothing else.
String _collapseWhitespace(String s) =>
    s.replaceAll(RegExp(r'\s+'), ' ').trim();
