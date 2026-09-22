import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:aim_core/aim_core.dart';
import 'package:web/web.dart' as web;

/// Statuses for which the Fetch spec forbids a body.
const _nullBodyStatuses = {101, 204, 205, 304};

/// Converts an Aim [Response] into a [web.Response].
///
/// `Set-Cookie` values joined with `\n` become separate headers. Bodies are
/// streamed through a `ReadableStream` so SSE and large responses flow
/// chunk by chunk. An empty body, or a status for which the Fetch spec
/// forbids a body (101, 204, 205, 304), is sent as `null`; in the latter
/// case the Dart body is still drained so any stream producer completes.
web.Response toWebResponse(Response response) {
  final headers = web.Headers();
  response.headers.forEach((key, value) {
    if (key.toLowerCase() == 'set-cookie') {
      for (final cookie in value.split('\n')) {
        if (cookie.isNotEmpty) headers.append(key, cookie);
      }
    } else {
      headers.append(key, value);
    }
  });

  final init = web.ResponseInit(status: response.statusCode, headers: headers);
  final hasBody =
      response.body.contentLength != 0 &&
      !_nullBodyStatuses.contains(response.statusCode);
  if (!hasBody) {
    // Consume and discard the Dart body so stream producers complete.
    response.read().listen(null, cancelOnError: true).cancel();
    return web.Response(null, init);
  }
  return web.Response(_toReadableStream(response.read()), init);
}

/// Wraps a Dart byte stream in a JS `ReadableStream`.
///
/// No backpressure: chunks are enqueued as they arrive.
web.ReadableStream _toReadableStream(Stream<List<int>> stream) {
  StreamSubscription<List<int>>? subscription;

  final source = JSObject();
  source['start'] = ((web.ReadableStreamDefaultController controller) {
    subscription = stream.listen(
      (chunk) => controller.enqueue(
        (chunk is Uint8List ? chunk : Uint8List.fromList(chunk)).toJS,
      ),
      onDone: () => controller.close(),
      onError: (Object error, StackTrace stackTrace) {
        web.console.error('Response stream failed: $error\n$stackTrace'.toJS);
        controller.error(error.toString().toJS);
      },
      cancelOnError: true,
    );
  }).toJS;
  source['cancel'] = (() {
    subscription?.cancel();
  }).toJS;

  return web.ReadableStream(source);
}
