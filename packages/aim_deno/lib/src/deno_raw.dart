import 'package:aim_deno/src/base_path.dart';
import 'package:aim_deno/src/deno_env.dart';
import 'package:aim_edge/adapter.dart';
import 'package:web/web.dart' as web;

/// What `serveDeno()` attaches to `Request.raw`.
final class DenoRaw implements EdgeRaw {
  DenoRaw(this.request, {this.basePath});

  @override
  final web.Request request;

  /// Removed from the front of [uri]'s path. See `stripBasePath`.
  final String? basePath;

  @override
  Uri get uri => stripUriBasePath(Uri.parse(request.url), basePath);

  @override
  EdgeEnv get env => const DenoEnv();
}
