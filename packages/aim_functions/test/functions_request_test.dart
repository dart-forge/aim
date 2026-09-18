import 'dart:async';
import 'dart:convert';

import 'package:aim_functions/src/functions_request.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';

void main() {
  test('carries the method, the uri, the headers and the body', () async {
    final request = shelf.Request(
      'POST',
      Uri.parse('https://example.com/users?page=2'),
      headers: {'content-type': 'application/json', 'x-trace': 'abc'},
      body: '{"name":"hana"}',
    );

    final aim = toAimRequest(request);

    expect(aim.method, 'POST');
    expect(aim.uri.path, '/users');
    expect(aim.queryParameters['page'], '2');
    expect(aim.headers['x-trace'], 'abc');
    expect(await utf8.decodeStream(aim.read()), '{"name":"hana"}');
  });

  test('keeps the shelf request reachable as raw', () {
    final request = shelf.Request('GET', Uri.parse('https://example.com/'));

    expect(toAimRequest(request).raw, same(request));
  });

  test('gives aim a headers map it can add to', () {
    // shelf hands out an unmodifiable map. aim's Request stores the map it is
    // given, so passing shelf's directly would make later writes throw from
    // somewhere that has nothing to do with this translation.
    final aim = toAimRequest(
      shelf.Request('GET', Uri.parse('https://example.com/')),
    );

    expect(() => aim.headers['x-added'] = 'ok', returnsNormally);
  });

  test(
    'streams the body lazily instead of materializing it upfront (A-065)',
    () async {
      // This is a measurement, not a formality: a test that merely reads a
      // large body proves nothing, since it would pass even if the body had
      // been buffered in full first. To prove laziness, the producer counts
      // how many chunks it has generated, and that counter is checked
      // *before* any reading happens and *while* reading progresses.
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

      final request = shelf.Request(
        'POST',
        Uri.parse('https://example.com/'),
        body: countedChunks(),
      );

      final aim = toAimRequest(request);

      // If the translation had materialized the body (e.g. by draining it
      // into a List), the producer would already have run to completion
      // here, before a single byte was read.
      expect(
        produced,
        0,
        reason: 'toAimRequest must not touch the body stream at all',
      );

      // Read one chunk at a time and record the producer's count at each
      // step. If chunks were generated on demand, the counter rises in
      // lock-step with consumption: exactly one new chunk per read.
      final iterator = StreamIterator(aim.read());
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
