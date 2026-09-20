---
title: Cloud Functions for Firebase - Aim Framework
description: Run an Aim application as a Cloud Functions for Firebase onRequest HTTP function. Dart support in firebase_functions is experimental; deploy with firebase deploy --only functions.
head:
  - - meta
    - name: keywords
      content: Dart Cloud Functions, Firebase Functions Dart, firebase_functions, Cloud Run, aim_functions, onRequest
---

# Cloud Functions for Firebase

An Aim application is not tied to the Dart VM. The routing, middleware, and `Context` API live in `aim_core`, and a runtime adapter connects them to a platform. `aim_server` is the adapter for `dart:io`, `aim_edge` is the adapter for Cloudflare workerd, and `aim_functions` is the adapter for Cloud Functions for Firebase.

```dart
import 'package:aim_functions/aim_functions.dart';
import 'package:firebase_functions/firebase_functions.dart' as ff;

void main(List<String> args) {
  final app = Aim()
    ..get('/', (c) async => c.text('Hello from Dart on Cloud Functions'));

  ff.runFunctions((firebase) {
    firebase.https.onRequest(name: 'api', app.serveFunction());
  });
}
```

`serveFunction()` turns an `Aim` app into a plain `shelf.Handler`. It doesn't call `firebase.https.onRequest` itself — you pass the handler to it, alongside whatever other triggers your Firebase project needs.

::: warning Experimental
`firebase_functions` marks its own status as "Experimental" and says only HTTPS triggers (what `aim_functions` uses) are currently supported in production; other trigger types have varying levels of support. This adapter inherits that status. `aim_functions` itself is not yet published to pub.dev — the interface above is what's implemented and tested, not a preview of something still being designed.
:::

## Prerequisites

- Dart 3.13 or later.
- The [Firebase CLI](https://firebase.google.com/docs/cli).
- A Firebase project for deploying. Local development doesn't need a real one — see [Routes and the function name](#routes-and-the-function-name) below.
- **`firebase_functions` 0.8.0 or later.** This is not a formality: on 0.6.x the local routing does not remove the function name before dispatching, so an app whose routes are written as `/` is unreachable locally — the function's root answers 404 because your handler is asked for `/api/`, and any deeper path is rejected by the SDK before your handler runs at all. Measured by running the same application against both versions and changing nothing else. `firebase init` has been seen to scaffold `^0.6.0`, so check what your `functions/pubspec.yaml` says rather than assuming.

## Create a project

```bash
firebase init functions   # choose Dart when prompted for a language
```

This creates a `functions` codebase with `functions/bin/server.dart` as its entry point. Write your app there, and pass `app.serveFunction()` to `firebase.https.onRequest`:

```dart
import 'package:aim_functions/aim_functions.dart';
import 'package:firebase_functions/firebase_functions.dart' as ff;

void main(List<String> args) {
  final app = Aim()
    ..get('/', (c) async => c.text('Hello from Dart!'))
    ..get('/users/:id', (c) async => c.json({'id': c.param('id')}));

  ff.runFunctions((firebase) {
    firebase.https.onRequest(name: 'api', app.serveFunction());
  });
}
```

## Routes and the function name

Write your routes without the function name as a prefix — `/`, not `/api/`; `/users/:id`, not `/api/users/:id` — the same as the example above, whatever name you pass to `onRequest`.

That's true for two different reasons depending on where the request comes from, and only one of them was checked against a running process:

- **Locally**, `firebase_functions` runs every registered function in one shared process and routes by path, stripping the function name before the request reaches your handler. This was run and confirmed with curl: starting the app above locally and requesting `GET /api/` and `GET /api/users/42` reached the app's `/` and `/users/:id` routes.
- **In production**, a deployed function is its own Cloud Run service — one function per service — so the function name lives in the service's URL rather than in the request path, and nothing needs to strip a prefix. This part is read from how `firebase_functions` is built to be deployed (the SDK takes a different, untouched-request code path once Cloud Run sets an internal target variable), not something observed against a real deployed function — this adapter's test suite has no Firebase project to deploy to.

## Middleware

Middleware packages depend on `aim_core`, not on `dart:io` or workerd, so they work unchanged here too: `aim_server_cors`, `aim_server_cookie`, `aim_server_form`, `aim_server_multipart` (parsing), `aim_server_logger`, `aim_server_sse`, `aim_server_jwt`, and `aim_server_basic_auth`.

`aim_server_static` and `UploadedFile.saveTo()` need the file system and are unavailable on Cloud Functions, the same as on Cloudflare Workers.

## Streaming

`aim_functions` passes request and response bodies through without materializing them — verified with a producer that only advances when a consumer actually reads. That's a property of the adapter itself, not of every path a request can take before reaching it, and the difference lands on exactly the path the local-development setup above runs on:

- `firebase_functions`'s local routing reads any `application/json` POST body into memory in full, to check whether it's a CloudEvent, before your handler ever runs.
- In production, that check doesn't happen: the request reaches your handler before the body is complete.

So streaming request bodies is real end-to-end once deployed, and not true for a JSON `POST` against the local dev server described above. A `GET` request, like the one in the examples on this page, has no body to buffer either way.

## Deploy

```bash
firebase deploy --only functions
```

This is the one genuinely unusual step compared to Node.js or Python functions: the Firebase CLI compiles your Dart code **on your machine** and uploads the resulting artifact, rather than pushing source for Cloud Build to compile remotely. There is no `aim build` step and no build target for Cloud Functions — the Firebase CLI does its own build, using whichever local Dart toolchain command it picks for your project's declared SDK constraint.

## Limitations

- Dart support in `firebase_functions` is experimental, independent of this adapter.
- Only `onRequest` is supported. `onCall` is Firebase's RPC convention — a JSON envelope with its own auth/App Check handshake, not ordinary HTTP routing — so it doesn't fit a request-in, response-out adapter; register it directly with `firebase.https.onCall` alongside `serveFunction()` for everything else.
- No background triggers. Firestore, Pub/Sub, Auth, Storage, and scheduled triggers aren't request/response shaped, so `aim_functions` doesn't wrap them; register those directly with `firebase_functions` too.

## Next Steps

- [Installation](/server/installation) - How Cloud Functions differs from `aim create` / `aim build`
- [Context](/server/concepts/context) - `c.variables` and the response helpers
- [Middleware](/server/middleware/) - Packages that run on every adapter
- [Cloud Functions for Firebase documentation](https://firebase.google.com/docs/functions/) - triggers, configuration, and the Firebase CLI
