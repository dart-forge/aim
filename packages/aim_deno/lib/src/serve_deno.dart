import 'dart:js_interop';

import 'package:aim_core/aim_core.dart';
import 'package:aim_deno/src/deno_raw.dart';
import 'package:aim_deno/src/interop.dart';
import 'package:aim_edge/adapter.dart';
import 'package:web/web.dart' as web;

/// Runs an [Aim] application on Deno-based runtimes.
extension AimDeno<E extends Variables> on Aim<E> {
  /// Registers this application as the Deno fetch handler.
  ///
  /// [basePath] is removed from the request path before routing. Supabase
  /// Edge Functions serve each function under `/<function-name>` and pass
  /// that segment to the handler, so pass the function name there. Deno
  /// Deploy and Netlify Edge serve at the root and need nothing.
  void serveDeno({String? basePath}) {
    aimFetchGlobal = ((web.Request request) => handleEdgeFetch(
      this,
      DenoRaw(request, basePath: basePath),
    ).toJS).toJS;
  }
}
