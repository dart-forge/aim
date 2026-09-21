/// String definitions for project templates
class Templates {
  static const projectPubspec = '''name: {{projectName}}
description: A web server built with Aim framework
version: 1.0.0

environment:
  sdk: ^3.13.0

dependencies:
  aim_server: ^0.2.0

dev_dependencies:
  lints: ^6.0.0
  test: ^1.25.6

aim:
  entry: bin/server.dart
''';

  static const projectReadme = '''# {{projectName}}

A web server project built with Aim framework.

## Setup

Install dependencies:
```bash
dart pub get
```

## Development

Start development server with hot reload:
```bash
aim dev
```

Or run directly:
```bash
dart run bin/server.dart
```

## Production Build

### Option 1: Native Executable

Compile to a native executable:
```bash
aim build
```

Run the executable:
```bash
./build/server
```

With environment variables:
```bash
PORT=3000 ./build/server
```

Or using a `.env` file (if your app uses a dotenv package):
```bash
./build/server
```

### Option 2: Docker

Build Docker image:
```bash
docker build -t {{projectName}} .
```

Run container:
```bash
docker run -p 8080:8080 {{projectName}}
```

With environment variables:
```bash
docker run -p 8080:8080 -e PORT=3000 -e ENV=production {{projectName}}
```

Or using an env file:
```bash
docker run -p 8080:8080 --env-file .env {{projectName}}
```

## Test

```bash
dart test
```

## Project Structure

- `bin/server.dart` - Server entry point
- `lib/src/server.dart` - Server implementation
- `test/{{projectName}}_test.dart` - Test files
- `Dockerfile` - Docker configuration for production
- `.dockerignore` - Files to exclude from Docker build

## About Aim Framework

For more details, see [Aim Documentation](https://github.com/yourusername/aim).
''';

  static const binServer = '''import 'dart:io';
import 'package:{{projectName}}/src/server.dart';

void main() async {
  final app = createApp();

  // Start server
  final server = await app.serve(
    host: InternetAddress.anyIPv4,
    port: 8080,
  );

  print('🚀 Server started: http://\${server.host}:\${server.port}');
}
''';

  static const libSrcServer = '''import 'dart:io';
import 'package:aim_server/aim_server.dart';

/// Create Aim application
Aim createApp() {
  final app = Aim();

  // Logging middleware
  app.use((c, next) async {
    print('[\${DateTime.now()}] \${c.method} \${c.path}');
    await next();
  });

  // Route definitions
  app
      // Home page
      .get('/', (c) async {
    return c.json({
      'message': 'Welcome to {{projectName}}!',
      'framework': 'Aim',
      'timestamp': DateTime.now().toIso8601String(),
    });
  })

      // GET request with parameters
      .get('/users/:id', (c) async {
    final id = c.param('id');
    return c.json({
      'userId': id,
      'name': 'User \$id',
    });
  })

      // Query parameter example
      .get('/search', (c) async {
    final query = c.queryParam('q', '');
    final page = c.queryParam('page', '1');

    return c.json({
      'query': query,
      'page': int.parse(page),
      'results': [],
    });
  })

      // POST request (JSON)
      .post('/api/users', (c) async {
    final data = await c.req.json();

    return c.json({
      'message': 'User created',
      'user': data,
      'id': 'user-\${DateTime.now().millisecondsSinceEpoch}',
    });
  })

      // Redirect
      .get('/old-path', (c) async {
    return c.redirect('/');
  });

  // 404 handler
  app.notFound((c) async {
    return c.json({
      'error': 'Not Found',
      'path': c.path,
    }, statusCode: 404);
  });

  // Error handler
  app.onError((error, c) async {
    print('Error: \$error');
    return c.json({
      'error': error.toString(),
    }, statusCode: 500);
  });

  return app;
}
''';

  static const testTest = '''import 'package:test/test.dart';

void main() {
  test('sample test', () {
    expect(true, isTrue);
  });

  // Future test examples:
  // - API endpoint tests
  // - Middleware tests
  // - Business logic tests
}
''';

  static const gitignore = '''
# Dart
.dart_tool/
.packages
build/
pubspec.lock

# IDE
.idea/
.vscode/
*.iml
''';

  static const dockerfile =
      '''# Official Dart image: https://hub.docker.com/_/dart
FROM dart:stable AS build

WORKDIR /app

# Copy and resolve dependencies
COPY pubspec.* ./
RUN dart pub get

# Copy app source code
COPY . .

# Ensure packages are up-to-date
RUN dart pub get --offline

# Compile to native executable
RUN dart compile exe bin/server.dart -o bin/server

# Build minimal serving image from AOT-compiled binary
FROM scratch

# Copy runtime dependencies and compiled binary
COPY --from=build /runtime/ /
COPY --from=build /app/bin/server /app/bin/

# Expose port (default: 8080)
EXPOSE 8080

# Start server
CMD ["/app/bin/server"]
''';

  static const dockerignore = '''# Dockerfile
.dockerignore
Dockerfile

# Build outputs
build/
*.exe
*.app

# Dart
.dart_tool/
.packages

# Version control
.git/
.gitignore
.github/

# IDE
.idea/
.vscode/
*.iml
*.code-workspace

# Documentation
README.md
CHANGELOG.md
LICENSE

# Tests
test/
*_test.dart

# CI/CD
.travis.yml
.gitlab-ci.yml

# Misc
*.log
*.tmp
.DS_Store
''';

  static const edgePubspec = '''name: {{projectName}}
description: An Aim application running on Cloudflare workerd
version: 1.0.0
publish_to: none

environment:
  sdk: ^3.13.0

dependencies:
  aim_edge: ^0.2.0

dev_dependencies:
  lints: ^6.0.0
  test: ^1.25.6

aim:
  target: edge
  entry: lib/main.dart
''';

  static const edgeMain = '''import 'package:aim_edge/aim_edge.dart';

void main() {
  final app = Aim();

  app.get('/', (c) async => c.text('Hello from {{projectName}} on workerd'));

  app.get('/users/:id', (c) async => c.json({'id': c.param('id')}));

  app.serveEdge();
}
''';

  static const edgeIndexMjs = '''import mod from '../build/edge/main.wasm';
import { CompiledApp } from '../build/edge/main.mjs';

let ready;

async function init() {
  const instance = await new CompiledApp(mod, { builtins: ['js-string'] })
    .instantiate({});
  instance.invokeMain(); // runs Dart main(), which calls app.serveEdge()
}

export default {
  async fetch(request, env, ctx) {
    ready ??= init();
    try {
      await ready;
    } catch (e) {
      ready = undefined; // allow the next request to retry initialisation
      throw e;
    }
    return globalThis.__aimFetch(request, env, ctx);
  },
};
''';

  static const edgeWranglerJsonc = '''{
  "name": "{{workerName}}",
  "main": "src/index.mjs",
  "compatibility_date": "2026-05-25",
  "vars": {
    "GREETING": "hello"
  }
}
''';

  static const edgeGitignore = '''
# Dart
.dart_tool/
.packages
build/
pubspec.lock

# wrangler / node
.wrangler/
node_modules/

# IDE
.idea/
.vscode/
*.iml
''';

  static const edgeReadme = '''# {{projectName}}

An [Aim](https://aim-dart.dev) application running on Cloudflare workerd.

## Development

```bash
dart pub get
aim dev            # compiles to wasm, starts wrangler dev, recompiles on change
```

## Deploy

```bash
aim build          # build/edge/main.wasm + main.mjs
npx wrangler@4 deploy
```

Bindings declared in `wrangler.jsonc` are available in handlers as `c.env`.
''';

  static const functionsPubspec = '''name: {{projectName}}
description: An Aim application running on Cloud Functions for Firebase
version: 1.0.0
publish_to: none

environment:
  sdk: ^3.13.0

dependencies:
  aim_functions: ^0.1.0
  firebase_functions: ^0.8.0

dev_dependencies:
  build_runner: ^2.4.0
  lints: ^6.0.0
  test: ^1.25.6

aim:
  target: functions
  entry: bin/server.dart
''';

  static const functionsServer =
      '''import 'package:aim_functions/aim_functions.dart';
import 'package:firebase_functions/firebase_functions.dart' as ff;
import 'package:{{projectName}}/src/server.dart';

void main(List<String> args) {
  final app = createApp();

  ff.runFunctions((firebase) {
    // The name becomes part of the URL: /<project>/<region>/api/...
    // The app's own routes are written without it; see lib/src/server.dart.
    firebase.https.onRequest(name: 'api', app.serveFunction());
  });
}
''';

  static const functionsApp =
      '''import 'package:aim_functions/aim_functions.dart';

/// Creates the Aim application.
///
/// Routes are written without the function name: `/`, not `/api/`. The name
/// passed to `onRequest` is removed before the request reaches the app, both
/// under the emulator and in a deployed function.
Aim createApp() {
  final app = Aim();

  app.get(
    '/',
    (c) async => c.json({
      'message': 'Welcome to {{projectName}}!',
      'framework': 'Aim',
    }),
  );

  app.get('/users/:id', (c) async => c.json({'userId': c.param('id')}));

  app.notFound(
    (c) async => c.json({'error': 'Not Found', 'path': c.path}, statusCode: 404),
  );

  return app;
}
''';

  static const functionsFirebaseJson = '''{
  "functions": [
    {
      "source": ".",
      "codebase": "default",
      "runtime": "dart3",
      "ignore": [
        "node_modules",
        ".git",
        ".dart_tool",
        ".firebase"
      ]
    }
  ],
  "emulators": {
    "functions": {
      "port": 5001
    },
    "ui": {
      "enabled": true
    },
    "singleProjectMode": true
  }
}
''';

  static const functionsFirebaserc = '''{
  "projects": {
    "default": "{{firebaseProject}}"
  }
}
''';

  static const functionsGitignore = '''
# Dart
.dart_tool/
build/
pubspec.lock

# Firebase
.firebase/
*.local
firebase-debug.log
firebase-debug.*.log
ui-debug.log

# IDE
.idea/
.vscode/
*.iml
''';

  static const functionsReadme = '''# {{projectName}}

An [Aim](https://aim-dart.dev) application running on Cloud Functions for
Firebase.

## Prerequisites

```bash
npm install -g firebase-tools
firebase login
firebase experiments:enable dartfunctions
```

Dart support in the Firebase CLI sits behind that experiment. Without it both
the emulator and `firebase deploy` refuse the `dart3` runtime.

## Development

```bash
dart pub get
aim dev
```

`aim dev` starts the Firebase emulator, which rebuilds the function on file
changes by itself. The app answers at
`http://localhost:5001/<project>/us-central1/api`. Change the port in
`firebase.json` under `emulators.functions.port`.

## Deploy

```bash
firebase use --add    # only needed once, if no Firebase project is bound yet
gcloud services enable run.googleapis.com --project <your-project-id>
firebase deploy --only functions
```

There is no build step to run first: the Firebase CLI compiles for Linux on
this machine and uploads the result.

The `gcloud` line is needed once per project. A Dart function is deployed as a
Cloud Run service, and `firebase deploy` does not enable the Cloud Run Admin
API for you. Without it the deploy builds and uploads, then fails with
`Cloud Run Admin API has not been used in project <id> before or it is
disabled`. Enabling takes a minute or two to propagate.

## Routes

Routes in `lib/src/server.dart` are written without the function name — `/`,
not `/api/`. The name passed to `onRequest` in `bin/server.dart` is removed
before the request reaches the app.
''';
}
