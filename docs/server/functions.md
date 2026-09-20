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
- The [Firebase CLI](https://firebase.google.com/docs/cli), logged in:

```bash
npm install -g firebase-tools
firebase login
```

- **Dart support switched on.** It sits behind an experiment flag; without it both the emulator and `firebase deploy` refuse the `dart3` runtime:

```bash
firebase experiments:enable dartfunctions
```

- A Firebase project for deploying. Local development doesn't need one — `aim dev` falls back to a `demo-` project id derived from your package name, which the emulator suite keeps entirely offline. Confirmed against a project with no `.firebaserc` at all: the emulator logged `Detected demo project ID "demo-probe-api"` and served normally.
- **`firebase_functions` 0.8.0 or later.** This is not a formality: on 0.6.x the local routing does not remove the function name before dispatching, so an app whose routes are written as `/` is unreachable locally — the function's root answers 404 because your handler is asked for `/api/`, and any deeper path is rejected by the SDK before your handler runs at all. Measured by running the same application against both versions and changing nothing else. `firebase init` has been seen to scaffold `^0.6.0`; `aim create --target functions` writes `^0.8.0`.

## Create a project

```bash
aim create my_api --target functions
```

It asks for a Firebase project id and writes it to `.firebaserc`; leave the answer empty to skip that file and bind a project later with `firebase use --add`. Pass `--firebase-project <id>` to answer without the prompt.

The result is flat — `firebase.json` sits next to `pubspec.yaml`, with `"source": "."` in its functions entry, so `aim dev` and the Firebase CLI agree on where the project root is:

```
my_api/
├── pubspec.yaml         # aim.target: functions
├── firebase.json
├── .firebaserc          # only when a Firebase project id was given
├── bin/server.dart      # runFunctions + onRequest
└── lib/src/server.dart  # createApp(): your routes
```

`bin/server.dart` hands the app to Firebase:

```dart
import 'package:aim_functions/aim_functions.dart';
import 'package:firebase_functions/firebase_functions.dart' as ff;
import 'package:my_api/src/server.dart';

void main(List<String> args) {
  final app = createApp();

  ff.runFunctions((firebase) {
    firebase.https.onRequest(name: 'api', app.serveFunction());
  });
}
```

## Run it locally

```bash
aim dev
```

This starts `firebase emulators:start --only functions`, forwarding `aim.env` from `pubspec.yaml` to the emulator process, which the function process it spawns inherits. The emulator runs `build_runner watch` for Dart functions itself, so edits to `lib/src/server.dart` are picked up while `aim dev` keeps running, without the CLI adding a second rebuild loop — which is why `--hot-reload` and `--watch` have no effect for this target. The first build takes on the order of 20 seconds before the emulator starts serving; a later edit is picked up in the tens of seconds, not instantly. The port comes from `firebase.json` (`emulators.functions.port`, 5001 by default) — `aim dev --port` is rejected for this target with an error pointing at that setting.

Requests reach the app at `http://localhost:5001/<project-id>/us-central1/api`; see [Routes and the function name](#routes-and-the-function-name) below.

## No build step

`aim build` does nothing for `target: functions` and says so — see [Deploy](#deploy) below for why.

## Routes and the function name

Write your routes without the function name as a prefix — `/`, not `/api/`; `/users/:id`, not `/api/users/:id` — the same as the example above, whatever name you pass to `onRequest`.

That's true for two different reasons depending on where the request comes from, and only one of them was checked against a running process:

- **Locally**, `firebase_functions` runs every registered function in one shared process and routes by path, stripping the function name before the request reaches your handler. Confirmed through `firebase emulators:start` against a project the Firebase CLI scaffolded: `GET /<project>/us-central1/api` and `.../api/users/42` reached the app's `/` and `/users/:id` routes, and `.../api/nope` came back as the app's own 404 rather than the emulator's. Also confirmed by running the entry point directly, without the emulator.
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

This is the one genuinely unusual step compared to Node.js or Python functions: the Firebase CLI compiles your Dart code **on your machine** and uploads the resulting artifact, rather than pushing source for Cloud Build to compile remotely. `aim build` does nothing for this target ([see above](#no-build-step)) — the Firebase CLI does its own build, using whichever local Dart toolchain command it picks for your project's declared SDK constraint.

## Limitations

- Dart support in `firebase_functions` is experimental, independent of this adapter.
- Only `onRequest` is supported. `onCall` is Firebase's RPC convention — a JSON envelope with its own auth/App Check handshake, not ordinary HTTP routing — so it doesn't fit a request-in, response-out adapter; register it directly with `firebase.https.onCall` alongside `serveFunction()` for everything else.
- No background triggers. Firestore, Pub/Sub, Auth, Storage, and scheduled triggers aren't request/response shaped, so `aim_functions` doesn't wrap them; register those directly with `firebase_functions` too.

## Next Steps

- [Installation](/server/installation) - How Cloud Functions differs from `aim create` / `aim build`
- [Context](/server/concepts/context) - `c.variables` and the response helpers
- [Middleware](/server/middleware/) - Packages that run on every adapter
- [Cloud Functions for Firebase documentation](https://firebase.google.com/docs/functions/) - triggers, configuration, and the Firebase CLI
