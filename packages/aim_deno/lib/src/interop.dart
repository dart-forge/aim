import 'dart:js_interop';

/// The global the JS entry module calls: `globalThis.__aimFetch(request)`.
@JS('__aimFetch')
external set aimFetchGlobal(JSFunction handler);
