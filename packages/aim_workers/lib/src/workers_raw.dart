import 'dart:js_interop';

import 'package:aim_edge/adapter.dart';
import 'package:aim_workers/src/workers_env.dart';
import 'package:web/web.dart' as web;

/// What `serveWorkers()` attaches to `Request.raw`.
final class WorkersRaw implements EdgeRaw {
  WorkersRaw(this.request, this.envObject, this.ctx);

  @override
  final web.Request request;

  @override
  Uri get uri => Uri.parse(request.url);

  /// The worker's `env` argument.
  final JSObject envObject;

  /// The worker's `ExecutionContext` argument.
  final JSObject ctx;

  @override
  EdgeEnv get env => WorkersEnv(envObject);
}
