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
    // The request could not be translated at all.
    stderr.writeln('Failed to process request: $e\n$st');
    return shelf.Response(400, body: 'Bad Request');
  }
  try {
    return toShelfResponse(response);
  } catch (e, st) {
    stderr.writeln('Failed to send response: $e\n$st');
    return shelf.Response.internalServerError(body: 'Internal Server Error');
  }
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
