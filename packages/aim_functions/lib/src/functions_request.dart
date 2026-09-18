import 'package:aim_core/aim_core.dart';
import 'package:shelf/shelf.dart' as shelf;

/// Typed access to the underlying shelf request.
extension ShelfRequestAccess on Request {
  /// The [shelf.Request] this request was created from, or `null` when the
  /// request was not produced by `serveFunction()` (for example in tests
  /// that construct a [Request] directly).
  shelf.Request? get shelfRequest {
    final r = raw;
    return r is shelf.Request ? r : null;
  }
}

/// Translates a shelf request — what Cloud Functions hands a handler — into
/// the request `aim_core` routes on.
///
/// Knows nothing about Cloud Functions: shelf is the whole contract here,
/// which is what makes this file reusable if the adapter is ever generalised.
Request toAimRequest(shelf.Request request) => Request(
  request.method,
  request.requestedUri,
  bodyContent: request.read(),
  // Copied, not passed through: shelf's map is unmodifiable and aim stores
  // the map it is given.
  headers: Map.of(request.headers),
  raw: request,
);
