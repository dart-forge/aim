import 'dart:async';

import 'package:aim_core/aim_core.dart';
import 'package:aim_functions/src/functions_response.dart';
import 'package:test/test.dart';

void main() {
  test('carries the status, the headers and the body', () async {
    final response = Response.text(
      'hello',
      statusCode: 201,
      headers: {'x-a': 'b'},
    );

    final shelfResponse = toShelfResponse(response);

    expect(shelfResponse.statusCode, 201);
    expect(shelfResponse.headers['x-a'], 'b');
    expect(await shelfResponse.readAsString(), 'hello');
  });

  test(
    'streams the body lazily instead of materializing it upfront (A-065)',
    () async {
      // Same measurement as functions_request_test.dart, mirrored for the
      // response side: a passing "read it and check the content" test would
      // not distinguish streaming from buffering. The producer's counter
      // does.
      //
      // 64 MiB, produced as 1024 chunks of 64 KiB each.
      const totalChunks = 1024;
      const chunkSize = 64 * 1024;
      var produced = 0;

      Stream<List<int>> countedChunks() async* {
        for (var i = 0; i < totalChunks; i++) {
          produced++;
          yield List<int>.filled(chunkSize, 0);
        }
      }

      final response = Response.stream(countedChunks());

      final shelfResponse = toShelfResponse(response);

      // The translation itself must not touch the body stream.
      expect(
        produced,
        0,
        reason: 'toShelfResponse must not touch the body stream at all',
      );

      final iterator = StreamIterator(shelfResponse.read());
      final producedAtEachStep = <int>[];
      while (await iterator.moveNext()) {
        producedAtEachStep.add(produced);
      }

      expect(producedAtEachStep.length, totalChunks);
      for (var i = 0; i < producedAtEachStep.length; i++) {
        expect(
          producedAtEachStep[i],
          i + 1,
          reason:
              'chunk $i should be produced exactly when it is read, not '
              'ahead of time',
        );
      }
    },
  );
}
