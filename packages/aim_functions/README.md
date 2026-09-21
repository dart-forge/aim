# aim_functions

Run an [Aim](https://pub.dev/packages/aim_core) application as a
[Cloud Functions for Firebase](https://pub.dev/packages/firebase_functions)
`onRequest` HTTP function.

Its only runtime dependency besides `aim_core` is `shelf`.
`serveFunction()` returns a plain `shelf.Handler`; `firebase_functions` is
what your own entry point (`runFunctions`, `firebase.https.onRequest`)
depends on to turn that handler into a deployable Cloud Function, not
something this package needs itself. That is why
`test/serve_functions_test.dart` never imports `firebase_functions` at
all.

```dart
import 'package:aim_functions/aim_functions.dart';
import 'package:firebase_functions/firebase_functions.dart' as ff;

void main(List<String> args) {
  final app = Aim()..get('/', (c) async => c.text('Hello from Dart!'));

  ff.runFunctions((firebase) {
    firebase.https.onRequest(name: 'api', app.serveFunction());
  });
}
```

The `firebase_functions` import is prefixed on purpose: it re-exports
shelf's `Request`/`Response` (`export 'package:shelf/shelf.dart' show
Request, Response;`), which are also `aim_core`'s own `Request`/`Response`
names reaching this file through the `aim_functions` barrel. Import both
unprefixed and the names collide — not in this snippet, which never
spells either name out, but the moment a caller reaches for
`Response.text(...)` instead of `c.text(...)`.

See `examples/functions-sample` in the repository for a runnable version,
including how to try it locally without a real Firebase project.

## Status: Dart on Cloud Functions is experimental

Requires **`firebase_functions` 0.8.0 or later**, confirmed on 0.8.0 through `firebase emulators:start`. On 0.6.x the local routing
does not remove the function name before dispatch, so an app whose routes are
written as `/` cannot be reached locally: the function root hands your handler
`/api/`, and deeper paths never arrive. Measured against both versions with
nothing else changed. `firebase init` has been seen to scaffold `^0.6.0`, so
check `functions/pubspec.yaml` rather than assuming.

`firebase_functions` itself calls its Dart support experimental — this
adapter inherits that. Only `onRequest` is supported; there is no
`serveFunction`-style helper for `onCall`. `onCall` is Firebase's RPC
convention (a JSON envelope with its own auth/App Check handshake, not
ordinary HTTP routing), so it doesn't fit an HTTP-request-in,
HTTP-response-out adapter — an app that needs callables should register them
directly with `firebase.https.onCall`, alongside `serveFunction()` for
everything else.

## Deploying is unusual: no cloud build step

`firebase deploy --only functions` **compiles on your machine** and uploads
the resulting artifact — it does not push source to Cloud Build the way
Node.js or Python functions do. Which toolchain command it uses depends on
the SDK constraint your project declares: `firebase_functions` picks between
`dart compile exe` and a `dart build cli` bundle, the latter from Dart 3.13
onwards because it cross-compiles and runs native build hooks the former
cannot. Do not build on either being the one you get. The entry
point the Firebase CLI expects is `functions/bin/server.dart` inside the
codebase directory `firebase init functions` creates. This repository does
not commit a `firebase.json` / `.firebaserc` for the example, since those
name a real Firebase project; see `examples/functions-sample/README.md`.

## Routes are written without the function name prefix

Registering a function with `name: 'api'` and calling it through the
shared local dev process (the example's "Try it locally" section) makes
clients address it at `/api/...`. Write your Aim routes without that
prefix regardless — `/`, not `/api/`; `/users/:id`, not `/api/users/:id`
— because the *mechanism* that makes this work is different locally than
in production, and the production one doesn't strip anything.

**Locally**, `firebase_functions` runs every registered function in one
shared process and routes by path: it strips the function name from the
request before calling the handler, rebuilding a new request whose
`requestedUri` no longer carries it (`lib/src/server.dart`'s
`_routeByPath` / `_withOriginalPath`). This was run and confirmed with
curl: `GET /api/` and `GET /api/users/42` reached the app's `/` and
`/users/:id` routes.

**In production**, `firebase_functions` takes a different branch
entirely (`_routeToTargetFunction`, selected when Cloud Run sets
`FUNCTION_TARGET`) that hands the handler the request completely
untouched. This was also run: `GCLOUD_PROJECT=demo-test
FUNCTION_TARGET=api dart run bin/server.dart`, then `curl`, gives
`GET /` → `200` and `GET /api/` → `404 Not Found` — the opposite of the
local dev routing above, because this branch strips nothing. Routes
still work at `/` in production, not because anything removes the
prefix, but because a deployed function is its own Cloud Run service —
one function per service — so the function name lives in the service's
address rather than in the request path, and the request simply arrives
at `/` already without needing to be rewritten. That last part — that
Cloud Run itself delivers the path at `/` — has been confirmed against a
real deployed function: `firebase deploy --only functions` of a
scaffolded app, then requests to the Cloud Run service's own address,
reached the app's `/users/:id` route and got the app's own 404 for an
unknown path.

`toAimRequest` uses `requestedUri`, not `url`, for this reason (and
because it's the absolute, leading-`/` path Aim's router expects —
`url`'s path never has the leading `/`); the two agree in every case
either branch of the SDK can construct, since neither ever mounts a
shelf `Router` or `Cascade` under a non-root path.

## Streaming

`toAimRequest` and `toShelfResponse` themselves pass the request/response
body through without materializing it — measured with a producer that
only advances when a consumer actually reads, not merely by pushing a
large body through and observing it arrive. Verified for request bodies
(client → function) and response bodies (function → client); see
`test/functions_request_test.dart` and `test/functions_response_test.dart`.

That is a property of the translation functions in isolation, not of
every path a request can take before reaching them — and the difference
matters on exactly the path the example's "Try it locally" section
tells you to run. `firebase_functions`'s local dev routing reads any
`application/json`
POST body into a `String` in full (to check whether it's a CloudEvent)
*before* dispatching to the handler at all. Measured: a JSON body sent in
three chunks with pauses between them arrives at the handler as a single
already-complete buffer, after the client has finished sending — the
handler is invoked only once buffering is done. In production
(`FUNCTION_TARGET` set — see [Routes](#routes-are-written-without-the-function-name-prefix)
above), that check does not run: the same request reaches the handler
before the body is complete, and reading it there advances only as the
client sends more.

So streaming is real end-to-end once deployed, and false for a JSON
`POST` on the local dev path the example's "Try it locally" section runs.
A `GET` (as in the example above) has no body to buffer either way,
which is why that section's own local test doesn't surface this.

## Logging

`aim_core` never prints. `serveFunction()` is the adapter that does the
logging: unhandled errors, requests that fail translation entirely, and a
response body stream that fails after the status line and headers are
already on the wire (where a thrown error would otherwise surface outside
every `try`/`catch` this adapter has) are all written to `stderr`. Cloud
Run (which is what a Cloud Function actually runs on) collects a
function's stdout and stderr into Cloud Logging, so nothing beyond
`stderr.writeln` is needed.

## Limitations

- Only `onRequest` is supported (see above).
- Dart support in `firebase_functions` itself is experimental; expect rough
  edges independent of this adapter.
