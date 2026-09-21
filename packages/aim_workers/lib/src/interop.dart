import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// The global the JS entry module calls: `globalThis.__aimFetch(request, env, ctx)`.
@JS('__aimFetch')
external set aimFetchGlobal(JSFunction handler);

/// `Headers.forEach` is missing from package:web 1.1.1.
extension HeadersForEach on web.Headers {
  external void forEach(JSFunction callback);
}
