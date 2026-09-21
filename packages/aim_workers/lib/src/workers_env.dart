import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:aim_edge/adapter.dart';

/// The worker's bindings object (`env`): vars, secrets and resource bindings
/// (KV, D1, R2, Durable Objects, service bindings). Hono calls this Bindings.
class WorkersEnv implements EdgeEnv {
  /// The underlying JS object, for bindings this class does not type.
  final JSObject raw;

  WorkersEnv(this.raw);

  /// A string var or secret, or `null` when absent or not a string.
  @override
  String? string(String name) {
    final value = raw.getProperty(name.toJS);
    return value.isA<JSString>() ? (value as JSString).toDart : null;
  }

  /// A resource binding (KV namespace, D1 database, ...), or `null` when
  /// absent or not an object. Use `dart:js_interop` to call it.
  @override
  JSObject? get(String name) {
    final value = raw.getProperty(name.toJS);
    return value.isA<JSObject>() ? value as JSObject : null;
  }

  /// Whether [name] exists on the bindings object.
  @override
  bool has(String name) => raw.has(name);
}
