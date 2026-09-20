import 'package:aim_core/aim_core.dart';
import 'package:shelf/shelf.dart' as shelf;

/// A name for [shelf.Request] that the public barrel can export without
/// colliding with `aim_core`'s own [Request] (the two can't both be
/// exported under the name `Request` from the same library — that's an
/// `ambiguous_export`, not merely an `ambiguous_import` a caller could work
/// around). This lets [ShelfRequestAccess.shelfRequest]'s return type be
/// written out by a caller who imports only `package:aim_functions`,
/// without adding `shelf` to their own pubspec.
typedef ShelfRequest = shelf.Request;

/// Typed access to the underlying shelf request.
extension ShelfRequestAccess on Request {
  /// The [ShelfRequest] this request was created from, or `null` when the
  /// request was not produced by `serveFunction()` (for example in tests
  /// that construct a [Request] directly).
  ShelfRequest? get shelfRequest {
    final r = raw;
    return r is ShelfRequest ? r : null;
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
