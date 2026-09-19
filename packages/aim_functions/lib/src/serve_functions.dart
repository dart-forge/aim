import 'dart:async';
import 'dart:io';

import 'package:aim_core/aim_core.dart';
import 'package:aim_functions/src/functions_request.dart';
import 'package:aim_functions/src/functions_response.dart';
import 'package:shelf/shelf.dart' as shelf;

/// Runs an [Aim] application as a Cloud Functions for Firebase HTTP function.
extension AimFunctions<E extends Variables> on Aim<E> {
  /// The handler to hand to `firebase.https.onRequest`.
  ///
  /// Returns a function rather than registering itself — `onRequest` takes
  /// the handler, unlike workerd where the adapter installs a global.
  ///
  /// ```dart
  /// void main(List<String> args) {
  ///   final app = Aim()..get('/', (c) async => c.text('hi'));
  ///
  ///   runFunctions((firebase) {
  ///     firebase.https.onRequest(name: 'api', app.serveFunction());
  ///   });
  /// }
  /// ```
  Future<shelf.Response> Function(shelf.Request) serveFunction() =>
      (request) => _handle(this, request);
}

Future<shelf.Response> _handle<E extends Variables>(
  Aim<E> app,
  shelf.Request request,
) async {
  Response response;
  try {
    response = await app.handle(
      toAimRequest(request),
      onUnhandledError: _logAndRespond,
    );
  } catch (e, st) {
    // toAimRequest is a synchronous field copy — it does not read the
    // body — so the only way this throws is a bug on this side (for
    // example a shelf.Request whose body was already consumed upstream).
    // That is server-side, so it gets a 500, not a 400.
    stderr.writeln('Failed to process request: $e\n$st');
    return shelf.Response.internalServerError(body: 'Internal Server Error');
  }
  shelf.Response shelfResponse;
  try {
    shelfResponse = toShelfResponse(response);
  } catch (e, st) {
    stderr.writeln('Failed to send response: $e\n$st');
    return shelf.Response.internalServerError(body: 'Internal Server Error');
  }
  // toShelfResponse can only fail synchronously, before any bytes are on
  // the wire. A failure in the body *stream* surfaces later, after
  // shelf_io has already written the status line and headers, which is
  // outside both try/catches above — logging it here, on the way into
  // shelf.Response, is the only place left that can see it.
  //
  // By the time a body-stream error happens, the status line and headers
  // are already on the wire, so there is no "pretend it never happened"
  // option — the choice is between handing the client a body that looks
  // complete but is silently broken, and letting the client see that the
  // transfer failed. This picks the second, unlike aim_server (which
  // logs and lets the response end as a clean, silently truncated 200).
  // `sink.addError` is what makes that possible: it both logs the
  // failure (an earlier version of this comment claimed the opposite —
  // that rethrowing would only recreate an unlogged crash — which is
  // wrong; `sink.addError` logs *and* forwards the error) and re-signals
  // it to shelf_io, which then ends the connection without a clean
  // terminating chunk, so the client's own HTTP stack reports the
  // failure instead of quietly finishing.
  //
  // `StreamTransformer.fromHandlers`'s `handleError` also stops the
  // stream at the first error, unlike the `Stream.handleError` this
  // replaces: `Stream.handleError` (without `cancelOnError`) logs an
  // error and then keeps forwarding whatever the producer emits
  // afterwards, so bytes produced after a reported failure were still
  // reaching the client — a corrupted response, not merely a truncated
  // one.
  return shelfResponse.change(
    body: shelfResponse.read().transform(
      StreamTransformer<List<int>, List<int>>.fromHandlers(
        handleError: (Object e, StackTrace st, EventSink<List<int>> sink) {
          stderr.writeln('Failed to send response body: $e\n$st');
          sink.addError(e, st);
          sink.close();
        },
      ),
    ),
  );
}

/// `aim_core` never prints — an adapter that wants unhandled errors logged
/// passes this. Cloud Run collects stdout and stderr into Cloud Logging, so
/// stderr is the whole mechanism; no logging package is needed.
Future<Response> _logAndRespond<E extends Variables>(
  Object error,
  StackTrace stackTrace,
  Context<E> c,
) async {
  stderr.writeln('Error: $error\n$stackTrace');
  return Response.internalServerError(body: 'Internal Server Error: $error');
}
