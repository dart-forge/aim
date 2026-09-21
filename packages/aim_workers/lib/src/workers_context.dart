import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:aim_core/aim_core.dart';
import 'package:aim_workers/src/cf_properties.dart';
import 'package:aim_workers/src/workers_raw.dart';

/// Access to Cloudflare workerd's own request metadata from a request served
/// by `aim_workers`. `c.env` (vars, secrets and resource bindings) is
/// declared on `Context` by `aim_edge` and works the same way here.
extension WorkersContext<E extends Variables> on Context<E> {
  /// The worker's `ExecutionContext` (`ctx`), used for `waitUntil` and
  /// `passThroughOnException`. `null` outside workerd.
  JSObject? get executionContext {
    final r = request.raw;
    return r is WorkersRaw ? r.ctx : null;
  }

  /// Cloudflare's `request.cf` metadata (colo, country, coordinates, ...).
  ///
  /// `null` when the request was not produced by the workerd adapter, or
  /// when the runtime did not populate `cf` (e.g. some local dev setups).
  CfProperties? get cf {
    final r = request.raw;
    if (r is! WorkersRaw) return null;
    final value = r.request.getProperty('cf'.toJS);
    return value.isA<JSObject>() ? CfProperties(value as JSObject) : null;
  }
}
