# aim_functions

Run an [Aim](https://pub.dev/packages/aim_core) application as a
[Cloud Functions for Firebase](https://pub.dev/packages/firebase_functions)
`onRequest` HTTP function.

**Not yet published to pub.dev.** This README describes the intended
interface; the `pub.dev` badge above will be filled in once it ships.

```dart
import 'package:aim_functions/aim_functions.dart';
import 'package:firebase_functions/firebase_functions.dart';

void main(List<String> args) {
  final app = Aim()..get('/', (c) async => c.text('Hello from Dart!'));

  runFunctions((firebase) {
    firebase.https.onRequest(name: 'api', app.serveFunction());
  });
}
```

See `examples/functions-sample` in the repository for a runnable version,
including how to try it locally without a real Firebase project.

## Status: Dart on Cloud Functions is experimental

`firebase_functions` itself calls its Dart support experimental — this
adapter inherits that. Only `onRequest` is supported; there is no
`serveFunction`-style helper for `onCall`. `onCall` is Firebase's RPC
convention (a JSON envelope with its own auth/App Check handshake, not
ordinary HTTP routing), so it doesn't fit an HTTP-request-in,
HTTP-response-out adapter — an app that needs callables should register them
directly with `firebase.https.onCall`, alongside `serveFunction()` for
everything else.

## Deploying is unusual: no cloud build step

`firebase deploy --only functions` **compiles on your machine** with
`dart compile exe` and uploads the resulting binary — it does not push
source to Cloud Build the way Node.js or Python functions do. The entry
point the Firebase CLI expects is `functions/bin/server.dart` inside the
codebase directory `firebase init functions` creates. This repository does
not commit a `firebase.json` / `.firebaserc` for the example, since those
name a real Firebase project; see `examples/functions-sample/README.md`.

## Routes are written without the function name prefix

Registering a function with `name: 'api'` makes clients address it at
`/api/...` (via the emulator's shared dev routing, a direct
`cloudfunctions.net/api/...` call, or a Firebase Hosting rewrite). That
prefix **does not reach the Aim app** — `firebase_functions` strips it
before calling the handler, so the app itself should register `/`, not
`/api/`, and `/users/:id`, not `/api/users/:id`.

This was measured, not assumed. `firebase_functions`' own routing
(`lib/src/server.dart`) never establishes a shelf `handlerPath` other than
the default root — it never uses `shelf_router`'s `Router.mount` or a
`Cascade`, so `shelf.Request.requestedUri` and `.url` always carry the same
path in every case this SDK can construct: it either hands the handler the
original, untouched request (the single-function-per-Cloud-Run-service
production path), or, in the local shared-process dev routing, builds a
*new* request with the prefix already removed from `requestedUri` itself
(confirmed by the package's own passing test,
`test/unit/server_test.dart` — `/echo` → handler sees `/`,
`/echo/other` → handler sees `/other`). `toAimRequest` uses `requestedUri`
for this reason (and because it's the absolute, leading-`/` path Aim's
router expects — `url`'s path never has the leading `/`). This was also
confirmed by actually running `examples/functions-sample` locally and
`curl`ing it: `GET /api/` and `GET /api/users/42` reached the app's `/` and
`/users/:id` routes.

## Streaming

Both directions pass the request/response body through without
materializing it — measured with a producer that only advances when a
consumer actually reads, not merely by pushing a large body through and
observing it arrive. Verified for request bodies (client → function) and
response bodies (function → client); see `test/functions_request_test.dart`
and `test/functions_response_test.dart`.

## Logging

`aim_core` never prints. `serveFunction()` is the adapter that does the
logging: unhandled errors, and requests that fail translation entirely, are
written to `stderr`. Cloud Run (which is what a Cloud Function actually
runs on) collects a function's stdout and stderr into Cloud Logging, so
nothing beyond `stderr.writeln` is needed.

## Limitations

- Only `onRequest` is supported (see above).
- Dart support in `firebase_functions` itself is experimental; expect rough
  edges independent of this adapter.
