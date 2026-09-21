import 'dart:js_interop';

import 'package:aim_core/aim_core.dart';
import 'package:aim_edge/adapter.dart';
import 'package:aim_workers/src/interop.dart';
import 'package:aim_workers/src/workers_raw.dart';
import 'package:web/web.dart' as web;

/// Runs an [Aim] application on Cloudflare workerd.
extension AimWorkers<E extends Variables> on Aim<E> {
  /// Registers this application as the worker's fetch handler.
  ///
  /// Sets `globalThis.__aimFetch` to a function `(request, env, ctx)` that
  /// returns a `Promise<Response>`. The JS entry module instantiates the wasm
  /// module, calls `main()` (which calls this), then forwards every `fetch`
  /// event to `__aimFetch`.
  void serveWorkers() {
    aimFetchGlobal = ((
      web.Request request,
      JSObject env,
      JSObject ctx,
    ) => handleEdgeFetch(this, WorkersRaw(request, env, ctx)).toJS).toJS;
  }
}
