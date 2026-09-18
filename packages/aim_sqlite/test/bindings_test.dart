import 'dart:io';
import 'dart:isolate';

import 'package:aim_sqlite/src/ffi/bindings.dart';
import 'package:test/test.dart';

void main() {
  group('SqliteLibrary.open', () {
    test('loads the platform library and reports a usable version', () {
      final lib = SqliteLibrary.open();

      // The floor comes from sqlite3_malloc64 (3.8.7), the newest function
      // in the symbol list -- not from WAL (3.7.0).
      expect(lib.versionNumber, greaterThanOrEqualTo(3008007));
    });

    test('names every place it looked when the library is missing', () {
      expect(
        () => SqliteLibrary.open(libraryPath: '/nonexistent/libsqlite3.dylib'),
        throwsA(
          isA<SqliteLibraryNotFoundException>().having(
            (e) => e.searched,
            'searched',
            // An explicit path is tried alone -- no fallback appended.
            equals(['/nonexistent/libsqlite3.dylib']),
          ),
        ),
      );
    });
  });

  group('SqliteLibrary.candidates', () {
    test('an explicit path wins outright, ignoring the environment', () {
      expect(
        SqliteLibrary.candidates('/explicit/path', {
          SqliteLibrary.environmentVariable: '/env/path',
        }),
        ['/explicit/path'],
      );
    });

    test('the environment override wins when no explicit path is given', () {
      expect(
        SqliteLibrary.candidates(null, {
          SqliteLibrary.environmentVariable: '/env/path',
        }),
        ['/env/path'],
      );
    });

    test('falls back to the platform defaults when neither is set', () {
      final result = SqliteLibrary.candidates(null, {});

      if (Platform.isMacOS) {
        expect(result, ['libsqlite3.dylib']);
      } else if (Platform.isWindows) {
        expect(result, ['sqlite3.dll']);
      } else {
        expect(result, ['libsqlite3.so.0', 'libsqlite3.so']);
      }
    });
  });

  group('SqliteLibrary SendPort safety', () {
    test('cannot cross a SendPort to another isolate', () async {
      final lib = SqliteLibrary.open();
      final receivePort = ReceivePort();
      addTearDown(receivePort.close);

      final isolate = await Isolate.spawn(
        _sendBackOwnPort,
        receivePort.sendPort,
      );
      addTearDown(isolate.kill);
      final childSendPort = await receivePort.first as SendPort;

      expect(() => childSendPort.send(lib), throwsArgumentError);
    });
  });
}

/// Isolate entry point: hands its own [SendPort] back to the caller so the
/// caller has a real cross-isolate port to send to.
void _sendBackOwnPort(SendPort parentSendPort) {
  final childReceivePort = ReceivePort();
  parentSendPort.send(childReceivePort.sendPort);
}
