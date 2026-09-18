import 'package:aim_core/aim_core.dart';
import 'package:shelf/shelf.dart' as shelf;

/// Translates an `aim_core` response into the shelf response Cloud Functions
/// sends back. Knows nothing about Cloud Functions, for the same reason
/// [toAimRequest] does not.
shelf.Response toShelfResponse(Response response) => shelf.Response(
  response.statusCode,
  body: response.read(),
  headers: response.headers,
);
