import 'package:aim_core/aim_core.dart';
import 'package:aim_edge/src/edge_env.dart';
import 'package:aim_edge/src/edge_raw.dart';

/// Access to the edge runtime from a request handled by `aim_edge`.
extension EdgeContext<E extends Variables> on Context<E> {
  /// The environment this request was served in, or `null` when the request
  /// did not come from an edge adapter.
  ///
  /// Read a var or secret with `c.env?.string('GREETING')`, or a resource
  /// binding with `c.env?.get('MY_KV')` on runtimes that have one.
  EdgeEnv? get env {
    final r = request.raw;
    return r is EdgeRaw ? r.env : null;
  }
}
