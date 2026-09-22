import 'dart:js_interop';

import 'package:aim_core/aim_core.dart';
import 'package:aim_edge/src/edge_raw.dart';
import 'package:web/web.dart' as web;

/// `Headers.forEach` is missing from package:web 1.1.1.
extension _HeadersForEach on web.Headers {
  external void forEach(JSFunction callback);
}

/// Converts an [EdgeRaw] into an Aim [Request].
///
/// The URI is taken from [EdgeRaw.uri], not re-derived from the underlying
/// request: an adapter serving under a path prefix (e.g. a Supabase Edge
/// Function's function name) already strips it there. Headers are copied
/// as-is. Bodies of non-GET/HEAD requests are read fully into memory.
Future<Request> toAimRequest(EdgeRaw raw) async {
  final headers = <String, String>{};
  raw.request.headers.forEach(
    (String value, String key) {
      headers[key] = value;
    }.toJS,
  );

  Object? body;
  if (raw.request.method != 'GET' && raw.request.method != 'HEAD') {
    final buffer = await raw.request.arrayBuffer().toDart;
    body = buffer.toDart.asUint8List();
  }

  return Request(
    raw.request.method,
    raw.uri,
    bodyContent: body,
    headers: headers,
    raw: raw,
  );
}
