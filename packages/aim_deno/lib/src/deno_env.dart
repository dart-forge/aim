import 'dart:js_interop';

import 'package:aim_edge/adapter.dart';

@JS('Deno.env.get')
external String? _denoEnvGet(String name);

@JS('Deno.env.has')
external bool _denoEnvHas(String name);

/// Deno's environment variables. Strings only — Deno has no resource
/// bindings, so [get] is always `null`.
final class DenoEnv implements EdgeEnv {
  const DenoEnv();

  @override
  String? string(String name) {
    // Deno throws when the process was started without --allow-env. Reading a
    // setting should not take the request down with it.
    try {
      return _denoEnvGet(name);
    } catch (_) {
      return null;
    }
  }

  @override
  JSObject? get(String name) => null;

  @override
  bool has(String name) {
    try {
      return _denoEnvHas(name);
    } catch (_) {
      return false;
    }
  }
}
