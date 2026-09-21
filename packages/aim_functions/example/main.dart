import 'package:aim_functions/aim_functions.dart';
import 'package:shelf/shelf.dart' as shelf;

/// `serveFunction()` turns an Aim application into a plain shelf handler,
/// which is what `firebase.https.onRequest` takes.
///
/// A real project's `bin/server.dart` registers it with the Firebase SDK:
///
/// ```dart
/// import 'package:firebase_functions/firebase_functions.dart' as ff;
///
/// void main(List<String> args) {
///   ff.runFunctions((firebase) {
///     firebase.https.onRequest(name: 'api', createApp().serveFunction());
///   });
/// }
/// ```
///
/// The `firebase_functions` import is prefixed there because it re-exports
/// shelf's `Request`/`Response`, which are also the names `aim_core` uses.
///
/// This file leaves that registration out so the example depends only on
/// what `aim_functions` itself does, and calls the handler directly instead.
void main() async {
  final handler = createApp().serveFunction();

  // Routes are written without the function name: '/', not '/api/'. The name
  // passed to onRequest lives in the service's address, not in the path the
  // app sees.
  final response = await handler(
    shelf.Request('GET', Uri.parse('http://x/users/42')),
  );

  print(response.statusCode); // 200
  print(await response.readAsString()); // {"userId":"42"}
}

/// The application, kept in its own function so the entry point can stay a
/// two-liner in a real project.
Aim createApp() {
  final app = Aim();

  app.get('/', (c) async => c.text('Hello from Dart!'));
  app.get('/users/:id', (c) async => c.json({'userId': c.param('id')}));

  return app;
}
