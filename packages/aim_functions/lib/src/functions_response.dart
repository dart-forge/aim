import 'package:aim_core/aim_core.dart';
import 'package:shelf/shelf.dart' as shelf;

/// Translates an `aim_core` response into the shelf response Cloud Functions
/// sends back. Knows nothing about Cloud Functions, for the same reason
/// [toAimRequest] does not.
///
/// `Set-Cookie` values joined with `\n` (which is what happens the second
/// time a handler calls `c.setCookie(...)`) are split into separate
/// headers. shelf accepts `Map<String, String | List<String>>`, so a
/// multi-value header is natively expressible; passing the joined string
/// straight through instead makes shelf_io throw a `FormatException` while
/// writing the response, which happens after this function has already
/// returned and is therefore invisible to any caller's `try`/`catch`.
shelf.Response toShelfResponse(Response response) => shelf.Response(
  response.statusCode,
  body: response.read(),
  headers: _splitSetCookie(response.headers),
);

Map<String, Object> _splitSetCookie(Map<String, String> headers) {
  final result = <String, Object>{};
  for (final entry in headers.entries) {
    result[entry.key] = entry.key.toLowerCase() == 'set-cookie'
        ? entry.value.split('\n').where((cookie) => cookie.isNotEmpty).toList()
        : entry.value;
  }
  return result;
}
