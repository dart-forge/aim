import 'package:aim_edge/src/edge_env.dart';
import 'package:web/web.dart' as web;

/// What an adapter attaches to `Request.raw` so the shared pipeline and the
/// platform extensions can reach the runtime's own objects.
abstract interface class EdgeRaw {
  /// The platform's incoming request.
  web.Request get request;

  /// The URI the application should route on.
  ///
  /// Usually `Uri.parse(request.url)`. An adapter serving under a path
  /// returns the URI with that path already removed.
  Uri get uri;

  /// The environment this request was served in.
  EdgeEnv get env;
}
