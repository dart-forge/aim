# functions-sample

Aim running as a Cloud Functions for Firebase HTTP function.

## Try it locally

`runFunctions` reads a project ID from the environment before it starts (it
does not need to be a real project for this), then serves plain HTTP on
`$PORT` (default `8080`):

```bash
GCLOUD_PROJECT=demo-test dart run bin/server.dart
```

The client addresses the function by the name passed to `onRequest`
(`'api'` here) — that prefix is stripped before Aim's own router ever sees
the request, so the app's routes stay `/` and `/users/:id`, not `/api/` and
`/api/users/:id`:

```bash
curl http://localhost:8080/api/
curl http://localhost:8080/api/users/42
```

## Deploy

This example intentionally has no `firebase.json` or `.firebaserc` — those
name a real Firebase project, which is the deploying developer's, not this
repository's. Create them once with the Firebase CLI:

```bash
firebase init functions   # choose Dart when prompted for a language
```

then point the generated `functions` codebase at this directory (or copy
`bin/server.dart` and `pubspec.yaml` into the `functions/` directory it
creates), and deploy:

```bash
firebase deploy --only functions
```

See `packages/aim_functions/README.md` for what happens during that deploy
and the current limitations (Dart on Cloud Functions is experimental).
