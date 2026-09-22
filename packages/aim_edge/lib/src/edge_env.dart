import 'dart:js_interop';

/// The environment a request was served in: vars, secrets, and — where the
/// runtime has them — resource handles.
///
/// Implemented by the per-runtime adapter packages.
abstract interface class EdgeEnv {
  /// A string var or secret, or `null` when absent or not a string.
  String? string(String name);

  /// A resource binding (KV namespace, D1 database, ...), or `null` when
  /// absent, not an object, or when the runtime has no such concept.
  ///
  /// Always `null` on Deno-based runtimes, which expose only string
  /// environment variables.
  JSObject? get(String name);

  /// Whether [name] exists.
  bool has(String name);
}
