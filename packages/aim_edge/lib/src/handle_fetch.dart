import 'dart:js_interop';

import 'package:aim_core/aim_core.dart';
import 'package:aim_edge/src/edge_raw.dart';
import 'package:aim_edge/src/edge_request.dart';
import 'package:aim_edge/src/edge_response.dart';
import 'package:web/web.dart' as web;

/// Runs [app] against [raw] and produces a [web.Response].
///
/// For use by adapter packages implementing a runtime's fetch entry point.
/// Two fallbacks keep a broken request or response from crashing the
/// isolate:
///
/// 1. If [Aim.handle] throws, logs to `console.error` and answers 400.
/// 2. If [toWebResponse] throws, logs to `console.error` and answers 500.
///
/// Unhandled errors inside a handler (with no [Aim.onError] registered) are
/// caught by [Aim.handle]'s `onUnhandledError`, logged, and answered as 500.
Future<web.Response> handleEdgeFetch<E extends Variables>(
  Aim<E> app,
  EdgeRaw raw,
) async {
  Response response;
  try {
    response = await app.handle(
      await toAimRequest(raw),
      onUnhandledError: _logAndRespond,
    );
  } catch (e, st) {
    web.console.error('Failed to process request: $e\n$st'.toJS);
    response = Response.text('Bad Request', statusCode: 400);
  }
  try {
    return toWebResponse(response);
  } catch (e, st) {
    web.console.error('Failed to send response: $e\n$st'.toJS);
    return web.Response(
      'Internal Server Error'.toJS,
      web.ResponseInit(status: 500),
    );
  }
}

Future<Response> _logAndRespond<E extends Variables>(
  Object error,
  StackTrace stackTrace,
  Context<E> c,
) async {
  web.console.error('Error: $error\n$stackTrace'.toJS);
  return Response.internalServerError(body: 'Internal Server Error: $error');
}
